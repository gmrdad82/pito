# frozen_string_literal: true

require "rails_helper"

# P42 — PATCH /chat/:uuid — inline conversation rename via Turbo Stream.

RSpec.describe "PATCH /chat/:uuid", type: :request do
  let!(:conversation) { create(:conversation, title: "Old Title") }

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

    it "updates the conversation title" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "My chat" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(conversation.reload.title).to eq("My chat")
    end

    it "returns 200" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "My chat" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:ok)
    end

    it "responds with a turbo-stream replace action" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "My chat" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include('action="replace"')
      expect(response.body).to include("conversation_row_#{conversation.uuid}")
    end

    it "includes the new title in the turbo-stream response" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "My chat" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response.body).to include("My chat")
    end

    it "includes a non-nil CompactTimeAgo timestamp in the replaced row (regression: was nil)" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "Renamed Chat" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      # The turbo-stream replace must include a formatted timestamp (e.g. "~Xm ago")
      # so the sidebar row shows the last-activity time rather than blank.
      expect(response.body).to match(/~\d+\w+ ago/)
    end

    it "rejects a blank title with 422" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "" },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(conversation.reload.title).to eq("Old Title")
    end

    it "rejects a whitespace-only title with 422" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "   " },
            headers: { "Accept" => "application/json" }

      expect(response).to have_http_status(:unprocessable_content)
      expect(conversation.reload.title).to eq("Old Title")
    end

    it "returns 404 for an unknown uuid" do
      patch conversation_path(uuid: "no-such-uuid"),
            params: { title: "Whatever" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:not_found)
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "redirects to root (auth wall)" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "My chat" },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(root_path)
    end

    it "does not update the title" do
      patch conversation_path(uuid: conversation.uuid),
            params: { title: "My chat" }

      expect(conversation.reload.title).to eq("Old Title")
    end
  end
end
