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

  # ── CSRF carve-out (the pito-tui contract) ───────────────────────────────────
  #
  # Request specs run with forgery protection OFF (test-env default), which is
  # exactly how the tui's body-less DELETE shipped broken: media_type-keyed
  # CSRF skipping never matches a request with no body (AppSignal incident,
  # 2026-07-14). These examples turn REAL forgery protection on to pin the
  # application_controller carve-out: token-less JSON-Accept DELETE passes,
  # token-less browser-shaped DELETE still refuses.

  describe "CSRF, with real forgery protection enabled" do
    # Authenticate FIRST (the login POST itself needs protection off, like
    # the browser page that carries a token), then flip real protection on
    # for the DELETE under test only.
    def with_forgery_protection
      prior = ActionController::Base.allow_forgery_protection
      ActionController::Base.allow_forgery_protection = true
      yield
    ensure
      ActionController::Base.allow_forgery_protection = prior
    end

    before { authenticate_via_totp }

    it "accepts a token-less DELETE with a JSON Accept header (pito-tui)" do
      with_forgery_protection do
        delete conversation_path(uuid: conversation.uuid),
               headers: { "Accept" => "application/json" }
      end
      expect(response).to have_http_status(:no_content)
    end

    it "still refuses a token-less browser-shaped (HTML) DELETE" do
      with_forgery_protection do
        delete conversation_path(uuid: conversation.uuid)
      end
      expect(response).not_to have_http_status(:no_content)
      expect(conversation.reload.deleting_at).to be_nil
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
