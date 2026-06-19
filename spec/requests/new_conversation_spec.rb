# frozen_string_literal: true

require "rails_helper"

# /new slash command creates a fresh Conversation and navigates to it.

RSpec.describe "POST /chat with /new", type: :request do
  let!(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
    # Clear login-round-trip events so per-test assertions start clean.
    conversation.events.destroy_all
  end

  # ── Authenticated path ─────────────────────────────────────────────────────

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "creates a new Conversation" do
      expect {
        post chat_path, params: { input: "/new", uuid: conversation.uuid }
      }.to change(Conversation, :count).by(1)
    end

    it "returns a Turbo Stream navigate action" do
      post chat_path, params: { input: "/new", uuid: conversation.uuid }
      expect(response).to have_http_status(:ok)
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="navigate"')
    end

    it "navigates to the new conversation's /chat/:uuid path" do
      post chat_path, params: { input: "/new", uuid: conversation.uuid }
      new_conversation = Conversation.order(:id).last
      expect(response.body).to include(new_conversation.uuid)
    end

    it "does NOT echo /new into the old conversation" do
      post chat_path, params: { input: "/new", uuid: conversation.uuid }
      expect(conversation.events.reload.where(kind: :echo).count).to eq(0)
    end

    it "does NOT enqueue a ChatDispatchJob" do
      expect {
        post chat_path, params: { input: "/new", uuid: conversation.uuid }
      }.not_to have_enqueued_job(ChatDispatchJob)
    end
  end

  # ── Unauthenticated path ───────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "does NOT create a new Conversation" do
      expect {
        post chat_path, params: { input: "/new", uuid: conversation.uuid }
      }.not_to change(Conversation, :count)
    end

    it "returns 204 (mandatory-auth error broadcast, no navigate)" do
      post chat_path, params: { input: "/new", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "broadcasts a mandatory-auth error event to the current conversation" do
      post chat_path, params: { input: "/new", uuid: conversation.uuid }
      error_event = conversation.events.where(kind: :error).last
      expect(error_event).to be_present
    end
  end
end
