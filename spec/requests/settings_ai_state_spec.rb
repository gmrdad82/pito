# frozen_string_literal: true

require "rails_helper"

# GET /settings/ai — the AI picker's JSON READ path (pito-tui parity): the
# exact state hash the /config ai web overlay renders, session-gated.
RSpec.describe "GET /settings/ai", type: :request do
  let!(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post chat_path, params: { input: "/login #{ROTP::TOTP.new(seed).now}", uuid: conversation.uuid }
  end

  describe "authenticated" do
    before do
      authenticate_via_totp
      allow(Ai::ModelCatalog).to receive(:models).and_return([ { id: "m-1", pinned: false } ])
      AppSetting.set("ai_provider", "opencode")
      AppSetting.set("ai_model", "m-1")
    end

    it "returns the full picker state with exact top-level keys" do
      get "/settings/ai", headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body.keys).to contain_exactly(
        "providers", "active_provider", "active_model", "effort",
        "favorites", "recents", "conversation_models"
      )
      expect(body["active_provider"]).to eq("opencode")
      expect(body["active_model"]).to eq("m-1")

      provider = body["providers"].find { |p| p["provider"] == "opencode" }
      expect(provider.keys).to contain_exactly("provider", "label", "key_present", "reasoning", "models")
      expect(provider["models"].first).to eq({ "id" => "m-1", "pinned" => false })
    end

    it "omits conversation_models without the uuid and fills them with it" do
      get "/settings/ai", headers: { "Accept" => "application/json" }
      expect(response.parsed_body["conversation_models"]).to eq([])

      # The /login turn already holds position 1 — append after it.
      turn = conversation.turns.create!(
        position: conversation.turns.maximum(:position).to_i + 1,
        input_kind: :chat, input_text: "@ai hi"
      )
      turn.events.create!(
        conversation:, kind: :ai,
        position: conversation.events.maximum(:position).to_i + 1,
        payload: { "provider" => "opencode", "model" => "m-1", "blocks" => [] }
      )

      get "/settings/ai", params: { conversation: conversation.uuid },
                          headers: { "Accept" => "application/json" }
      expect(response.parsed_body["conversation_models"]).to eq([ "opencode/m-1" ])
    end

    it "shrugs off an unknown conversation uuid" do
      get "/settings/ai", params: { conversation: "no-such-uuid" },
                          headers: { "Accept" => "application/json" }
      expect(response).to have_http_status(:ok)
      expect(response.parsed_body["conversation_models"]).to eq([])
    end
  end

  it "anonymous → 401" do
    get "/settings/ai", headers: { "Accept" => "application/json" }
    expect(response).to have_http_status(:unauthorized)
  end
end
