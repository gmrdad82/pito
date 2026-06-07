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

    it "destroys the conversation record" do
      expect {
        delete conversation_path(uuid: conversation.uuid)
      }.to change(Conversation, :count).by(-1)
    end

    it "also destroys dependent turns" do
      # Use a fresh conversation so position sequences don't collide with
      # the turns created during TOTP auth.
      other = create(:conversation, :named)
      create(:turn, conversation: other, position: 1)
      expect {
        delete conversation_path(uuid: other.uuid)
      }.to change(Turn, :count).by(-1)
    end

    it "also destroys dependent events" do
      other = create(:conversation, :named)
      turn = create(:turn, conversation: other, position: 1)
      create(:event, conversation: other, turn: turn)
      expect {
        delete conversation_path(uuid: other.uuid)
      }.to change(Event, :count).by(-1)
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

    it "does not destroy the conversation" do
      expect {
        delete conversation_path(uuid: conversation.uuid)
      }.not_to change(Conversation, :count)
    end
  end
end
