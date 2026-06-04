# frozen_string_literal: true

require "rails_helper"

# P40 — /resume slash command populates #pito-sidebar with the conversation list.

RSpec.describe "POST /chat with /resume", type: :request do
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
    before do
      authenticate_via_totp
      # Create a couple of extra conversations so the list is non-empty.
      Conversation.create!
      Conversation.create!
    end

    it "returns 200 OK" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      expect(response).to have_http_status(:ok)
    end

    it "responds with a Turbo Stream content type" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
    end

    it "returns a turbo-stream targeting pito-sidebar" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      expect(response.body).to include('target="pito-sidebar"')
    end

    it "includes at least one data-conversation-uuid attribute in the response" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      expect(response.body).to include("data-conversation-uuid")
    end

    it "does NOT echo /resume or enqueue a ChatDispatchJob" do
      expect {
        post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      }.not_to have_enqueued_job(ChatDispatchJob)
    end

    it "does NOT create a Turn" do
      expect {
        post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      }.not_to change(Turn, :count)
    end

    it "marks the current conversation row with is-current" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      # The current uuid should appear alongside is-current in the body
      expect(response.body).to include("is-current")
      expect(response.body).to include(conversation.uuid)
    end

    it "wraps the conversation list in the Sidebar shell (aside element)" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      # Pito::Sidebar::Component renders an <aside> — verify it is present so the
      # list is shown as a side panel, not a full-width block.
      expect(response.body).to include("<aside")
    end
  end

  # ── Unauthenticated path ───────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "returns 204 No Content (mandatory-auth path)" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT return a Turbo Stream targeting pito-sidebar" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      expect(response.body).not_to include('target="pito-sidebar"')
    end

    it "broadcasts a mandatory-auth error event to the current conversation" do
      post chat_path, params: { input: "/resume", uuid: conversation.uuid }
      error_event = conversation.events.where(kind: :error).last
      expect(error_event).to be_present
    end
  end
end
