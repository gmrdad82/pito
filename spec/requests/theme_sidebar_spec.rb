# frozen_string_literal: true

require "rails_helper"

# P8 — Bare /themes opens the theme picker sidebar (Turbo Stream update to #pito-sidebar).

RSpec.describe "POST /chat with bare /themes", type: :request do
  let!(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
    conversation.events.destroy_all
  end

  # ── Authenticated path ───────────────────────────────────────────────────────

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "returns 200 OK" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response).to have_http_status(:ok)
    end

    it "responds with a Turbo Stream content type" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
    end

    it "returns a turbo-stream targeting pito-sidebar" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include('target="pito-sidebar"')
    end

    it "includes theme rows in the sidebar body" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include("pito-theme-row")
    end

    it "includes data-theme-name attributes on theme rows" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include("data-theme-name")
    end

    it "marks the current theme row with is-current" do
      current = AppSetting.theme
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include("is-current")
      expect(response.body).to include(current)
    end

    it "wraps the theme list in the Sidebar shell (aside element)" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include("<aside")
    end

    it "does NOT echo /themes or enqueue a ChatDispatchJob" do
      expect {
        post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      }.not_to have_enqueued_job(ChatDispatchJob)
    end

    it "does NOT create a Turn" do
      expect {
        post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      }.not_to change(Turn, :count)
    end

    it "includes the Dark section header" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include("Dark")
    end

    it "includes the Light section header" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include("Light")
    end

    it "mounts the pito--theme-nav stimulus controller on the list container" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).to include("pito--theme-nav")
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "returns 204 No Content (mandatory-auth path)" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT return a Turbo Stream targeting pito-sidebar" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      expect(response.body).not_to include('target="pito-sidebar"')
    end

    it "broadcasts a mandatory-auth error event to the current conversation" do
      post chat_path, params: { input: "/themes", uuid: conversation.uuid }
      error_event = conversation.events.where(kind: :error).last
      expect(error_event).to be_present
    end
  end
end
