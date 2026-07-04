# frozen_string_literal: true

require "rails_helper"
require "action_cable/test_helper"

RSpec.describe "PATCH /settings/theme", type: :request do
  include ActionCable::TestHelper

  # ── Auth helper ──────────────────────────────────────────────────────────────

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: Conversation.singleton.uuid }
  end

  # ── Authenticated path ───────────────────────────────────────────────────────

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "persists a known theme and returns 204" do
      AppSetting.where(key: AppSetting::THEME_KEY).delete_all

      patch settings_theme_path,
            params:  { theme: "dracula" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(AppSetting.theme).to eq("dracula")
    end

    it "round-trips back to tokyo-night" do
      AppSetting.theme = "dracula"

      patch settings_theme_path,
            params:  { theme: "tokyo-night" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "broadcasts #pito-settings with the new data-theme to pito:global" do
      AppSetting.theme = "tokyo-night"

      expect {
        patch settings_theme_path,
              params:  { theme: "dracula" },
              headers: { "Accept" => "application/json" }
      }.to have_broadcasted_to("pito:global").with { |msg|
        html = msg.is_a?(Hash) ? msg.values.join : msg.to_s
        expect(html).to include('action="replace"')
        expect(html).to include("pito-settings")
        expect(html).to include('data-theme="dracula"')
      }
    end

    it "rejects an unknown theme slug with 422" do
      AppSetting.theme = "tokyo-night"

      patch settings_theme_path,
            params:  { theme: "nonexistent-theme" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(AppSetting.theme).to eq("tokyo-night")
    end

    it "does not change AppSetting for an unknown slug" do
      AppSetting.theme = "dracula"

      patch settings_theme_path,
            params:  { theme: "bogus" },
            headers: { "Accept" => "application/json" }

      expect(AppSetting.theme).to eq("dracula")
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    # JSON-format requests get an explicit 401 (Sessions::AuthConcern) — the
    # redirect-to-root auth wall is a browser affordance.
    it "rejects with 401 JSON (auth wall)" do
      patch settings_theme_path,
            params:  { theme: "dracula" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthenticated")
    end

    it "does not change AppSetting" do
      AppSetting.theme = "tokyo-night"

      patch settings_theme_path, params: { theme: "dracula" }

      expect(AppSetting.theme).to eq("tokyo-night")
    end
  end
end
