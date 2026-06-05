# frozen_string_literal: true

require "rails_helper"

RSpec.describe "POST /settings/expand_all", type: :request do
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

    it "sets expand_all to true and returns 204" do
      AppSetting.where(key: AppSetting::EXPAND_ALL_KEY).delete_all

      post settings_toggle_expand_all_path,
           params:  { expand_all: true },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(AppSetting.expand_all?).to be true
    end

    it "sets expand_all to false and returns 204" do
      AppSetting.expand_all = true

      post settings_toggle_expand_all_path,
           params:  { expand_all: false },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:no_content)
      expect(AppSetting.expand_all?).to be false
    end

    it "toggles expand_all from false to true" do
      AppSetting.expand_all = false

      post settings_toggle_expand_all_path,
           params:  { expand_all: true },
           headers: { "Accept" => "application/json" }

      expect(AppSetting.expand_all?).to be true
    end

    it "toggles expand_all from true to false" do
      AppSetting.expand_all = true

      post settings_toggle_expand_all_path,
           params:  { expand_all: false },
           headers: { "Accept" => "application/json" }

      expect(AppSetting.expand_all?).to be false
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "redirects to root (auth wall)" do
      post settings_toggle_expand_all_path,
           params:  { expand_all: true },
           headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(root_path)
    end

    it "does not change AppSetting" do
      AppSetting.expand_all = false

      post settings_toggle_expand_all_path, params: { expand_all: true }

      expect(AppSetting.expand_all?).to be false
    end
  end
end
