# frozen_string_literal: true

require "rails_helper"

# PATCH /chat/:uuid with scope params (shift+tab channel scope / shift+space
# stats period). Persists onto the conversation so a reload restores them.
#   scope save → 204, persists scope_channel/stats_period, no Turbo Stream,
#                title + draft untouched.

RSpec.describe "Conversation scope persistence", type: :request do
  let!(:conversation) { create(:conversation, title: "Old Title") }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
    conversation.events.destroy_all
  end

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "defaults to @all / 7d for a fresh conversation" do
      expect(conversation.scope_channel).to eq("@all")
      expect(conversation.stats_period).to eq("7d")
    end

    it "returns 204 No Content and persists both scope params" do
      patch conversation_path(uuid: conversation.uuid),
            params: { scope_channel: "@manfygreats", stats_period: "28d" }

      expect(response).to have_http_status(:no_content)
      conversation.reload
      expect(conversation.scope_channel).to eq("@manfygreats")
      expect(conversation.stats_period).to eq("28d")
    end

    it "persists a single scope param without disturbing the other" do
      patch conversation_path(uuid: conversation.uuid), params: { stats_period: "lifetime" }

      expect(response).to have_http_status(:no_content)
      conversation.reload
      expect(conversation.stats_period).to eq("lifetime")
      expect(conversation.scope_channel).to eq("@all")
    end

    it "does NOT change the title or draft" do
      conversation.update!(draft: "my draft")

      patch conversation_path(uuid: conversation.uuid),
            params: { scope_channel: "@manfygreats", stats_period: "28d" }

      conversation.reload
      expect(conversation.title).to eq("Old Title")
      expect(conversation.draft).to eq("my draft")
    end

    it "does NOT return a turbo-stream response" do
      patch conversation_path(uuid: conversation.uuid),
            params: { scope_channel: "@manfygreats" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:no_content)
      expect(response.body).to be_empty
    end
  end

  describe "when unauthenticated" do
    it "redirects to root and does not persist scope" do
      patch conversation_path(uuid: conversation.uuid),
            params: { scope_channel: "@manfygreats", stats_period: "28d" }

      expect(response).to redirect_to(root_path)
      conversation.reload
      expect(conversation.scope_channel).to eq("@all")
      expect(conversation.stats_period).to eq("7d")
    end
  end
end
