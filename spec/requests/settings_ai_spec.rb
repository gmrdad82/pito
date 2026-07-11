# frozen_string_literal: true

require "rails_helper"

RSpec.describe "PATCH /settings/ai", type: :request do
  # ── Auth helper (mirrors settings_theme_spec) ────────────────────────────────

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: Conversation.singleton.uuid }
  end

  def patch_ai(params)
    patch settings_ai_path, params: params, headers: { "Accept" => "application/json" }, as: :json
  end

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "stores a stripped API key in the encrypted kv store and never echoes it back" do
      patch_ai(api_key: "  sk-live-test  ")

      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("opencode_api_key")).to eq("sk-live-test")
      expect(response.parsed_body["key_present"]).to be(true)
      expect(response.body).not_to include("sk-live-test")
    end

    it "clears the stored key with clear_key" do
      AppSetting.set("opencode_api_key", "sk-old")

      patch_ai(clear_key: true)

      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("opencode_api_key")).to be_blank
      expect(response.parsed_body["key_present"]).to be(false)
    end

    it "persists a model known to the catalog and stamps the active provider" do
      allow(::Ai::ModelCatalog).to receive(:models).with(provider: :opencode)
        .and_return([ { id: "claude-sonnet-5", pinned: false } ])

      patch_ai(model: "claude-sonnet-5")

      expect(response).to have_http_status(:ok)
      expect(AppSetting.get("ai_model")).to eq("claude-sonnet-5")
      expect(AppSetting.get("ai_provider")).to eq("opencode")
      expect(response.parsed_body["model"]).to eq("claude-sonnet-5")
    end

    it "rejects a model the catalog does not know with 422 and persists nothing" do
      allow(::Ai::ModelCatalog).to receive(:models).with(provider: :opencode)
        .and_return([ { id: "claude-sonnet-5", pinned: false } ])

      patch_ai(model: "ghost-model")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("unknown_model")
      expect(AppSetting.get("ai_model")).to be_blank
    end

    it "rejects an unknown provider with 422" do
      patch_ai(provider: "nope", api_key: "sk-x")

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.parsed_body["error"]).to eq("unknown_provider")
      expect(AppSetting.get("nope_api_key")).to be_blank
    end
  end

  describe "when unauthenticated" do
    it "rejects with 401 JSON (auth wall) and stores nothing" do
      patch_ai(api_key: "sk-anon")

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthenticated")
      expect(AppSetting.get("opencode_api_key")).to be_blank
    end
  end
end
