# frozen_string_literal: true

require "rails_helper"

RSpec.describe "DELETE /chat/:uuid", type: :request do
  let!(:conversation) { create(:conversation, :named) }

  # ── Auth helper ──────────────────────────────────────────────────────────────

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

    it "responds 204 No Content" do
      delete conversation_path(uuid: conversation.uuid)
      expect(response).to have_http_status(:no_content)
    end

    it "marks the conversation deleting WITHOUT destroying it synchronously (async)" do
      expect {
        delete conversation_path(uuid: conversation.uuid)
      }.not_to change(Conversation, :count)
      expect(conversation.reload).to be_deleting
    end

    it "enqueues DeleteConversationJob for the conversation (the slow cascade runs off-request)" do
      allow(DeleteConversationJob).to receive(:perform_later)
      delete conversation_path(uuid: conversation.uuid)
      expect(DeleteConversationJob).to have_received(:perform_later).with(conversation.id)
    end

    it "returns 404 for an unknown uuid" do
      delete conversation_path(uuid: "no-such-uuid-at-all")
      expect(response).to have_http_status(:not_found)
    end

    it "responds 204 even when the deleted conversation is the current one" do
      # Deleting the conversation you are currently in still returns 204;
      # the redirect to "/" happens client-side.
      delete conversation_path(uuid: conversation.uuid)
      expect(response).to have_http_status(:no_content)
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "redirects to root (auth wall)" do
      delete conversation_path(uuid: conversation.uuid)
      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(root_path)
    end

    it "does not mark the conversation deleting" do
      expect {
        delete conversation_path(uuid: conversation.uuid)
      }.not_to change(Conversation, :count)
      expect(conversation.reload.deleting_at).to be_nil
    end
  end
end
