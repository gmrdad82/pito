# frozen_string_literal: true

require "rails_helper"

# SyncController — single mutation endpoint for the server-side sync
# state (2026-05-25 sync-rebuild). The before_action auth guards from
# `Sessions::AuthConcern` are stubbed for the spec; they have full
# coverage elsewhere. What we lock here is the cascade semantics:
# every cascaded target row is written AND a `pito:sync_state`
# broadcast fires per target.
RSpec.describe "POST /sync/toggle", type: :request do
  # `ApplicationController` opts in to `allow_browser versions: :modern`
  # (UA gate) AND Rails 8's `ActionDispatch::HostAuthorization` (host
  # allowlist). Default test Host is `www.example.com`, blocked by the
  # host gate; default User-Agent is empty, blocked by the browser
  # gate. Set both to satisfy the chain before the action runs.
  let(:modern_ua) do
    "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
  end
  let(:headers) { { "HTTP_USER_AGENT" => modern_ua, "HOST" => "localhost" } }

  before do
    # Bypass cookie auth + TOTP gate; the controller logic under test
    # does not depend on the user identity, only on the request
    # making it past the before_actions.
    allow_any_instance_of(ApplicationController).to receive(:authenticate_session!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:require_totp_configured!).and_return(true)
    allow_any_instance_of(ApplicationController).to receive(:reset_current_after_request).and_yield
  end

  describe "happy path — toggling a leaf panel target" do
    it "flips the AppSetting row from default-yes to no" do
      post "/sync/toggle", params: { target: "home.security" }, headers: headers
      puts "DEBUG status=#{response.status} body=#{response.body[0..500].inspect}" unless response.no_content?
      expect(response).to have_http_status(:no_content)
      expect(AppSetting.sync_enabled?("home.security")).to be(false)
    end

    it "broadcasts ONE sync_state envelope on pito:sync_state" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_sync_state)
        .with(target: "home.security", enabled: false)
        .once
      post "/sync/toggle", params: { target: "home.security" }, headers: headers
    end

    it "toggles back to true on a second call" do
      post "/sync/toggle", params: { target: "home.security" }, headers: headers
      post "/sync/toggle", params: { target: "home.security" }, headers: headers
      expect(AppSetting.sync_enabled?("home.security")).to be(true)
    end
  end

  describe "cascade — toggling a parent panel" do
    it "writes home.stack and every registered child" do
      post "/sync/toggle", params: { target: "home.stack" }, headers: headers
      expect(AppSetting.sync_enabled?("home.stack")).to be(false)
      expect(AppSetting.sync_enabled?("home.stack.meilisearch")).to be(false)
      expect(AppSetting.sync_enabled?("home.stack.voyage")).to be(false)
      expect(AppSetting.sync_enabled?("home.stack.postgres")).to be(false)
      expect(AppSetting.sync_enabled?("home.stack.assets")).to be(false)
    end

    it "broadcasts one envelope per cascaded target (5 total)" do
      expect(Pito::CableBroadcaster).to receive(:broadcast_sync_state).exactly(5).times
      post "/sync/toggle", params: { target: "home.stack" }, headers: headers
    end
  end

  describe "cascade — toggling 'app' (master)" do
    it "writes every known target" do
      post "/sync/toggle", params: { target: "app" }, headers: headers
      expect(AppSetting.sync_enabled?("app")).to be(false)
      Pito::SyncTargets.all.each do |t|
        expect(AppSetting.sync_enabled?(t)).to be(false), "expected #{t} to be disabled after master toggle"
      end
    end

    it "broadcasts one envelope per cascaded target (1 master + N targets)" do
      expected = 1 + Pito::SyncTargets.all.length
      expect(Pito::CableBroadcaster).to receive(:broadcast_sync_state).exactly(expected).times
      post "/sync/toggle", params: { target: "app" }, headers: headers
    end
  end

  describe "unknown target" do
    it "returns 404 without writing or broadcasting" do
      expect(Pito::CableBroadcaster).not_to receive(:broadcast_sync_state)
      post "/sync/toggle", params: { target: "bogus.thing" }, headers: headers
      expect(response).to have_http_status(:not_found)
      expect(AppSetting.where("key LIKE ?", "sync.bogus%").count).to eq(0)
    end

    it "returns 404 for an empty target" do
      post "/sync/toggle", params: { target: "" }, headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "missing target param" do
    it "returns 404" do
      post "/sync/toggle", headers: headers
      expect(response).to have_http_status(:not_found)
    end
  end
end
