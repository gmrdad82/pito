# frozen_string_literal: true

require "rails_helper"

# PATCH /chat/:uuid with draft params.
# Verifies the dual-behavior of ConversationsController#update:
#   - draft save → 204, persists draft, no Turbo Stream
#   - rename     → 200 + Turbo Stream row replace (existing behaviour intact)

RSpec.describe "Conversation draft autosave", type: :request do
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

    # ── Draft save ─────────────────────────────────────────────────────────────

    describe "PATCH with draft param (draft-save path)" do
      it "returns 204 No Content" do
        patch conversation_path(uuid: conversation.uuid),
              params: { draft: "hi" }

        expect(response).to have_http_status(:no_content)
      end

      it "persists the draft value" do
        patch conversation_path(uuid: conversation.uuid),
              params: { draft: "hello world" }

        expect(conversation.reload.draft).to eq("hello world")
      end

      it "allows clearing the draft (blank string → nil stored)" do
        conversation.update!(draft: "existing draft")

        patch conversation_path(uuid: conversation.uuid),
              params: { draft: "" }

        expect(response).to have_http_status(:no_content)
        expect(conversation.reload.draft).to be_nil
      end

      it "does NOT return a turbo-stream response" do
        patch conversation_path(uuid: conversation.uuid),
              params: { draft: "hi" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:no_content)
        expect(response.body).to be_empty
      end

      it "does NOT change the title" do
        patch conversation_path(uuid: conversation.uuid),
              params: { draft: "hi" }

        expect(conversation.reload.title).to eq("Old Title")
      end
    end

    # ── Rename (existing behaviour) ────────────────────────────────────────────

    describe "PATCH with title param (rename path)" do
      it "returns 200 with a turbo-stream replace action" do
        patch conversation_path(uuid: conversation.uuid),
              params: { title: "New Title" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(response).to have_http_status(:ok)
        expect(response.content_type).to include("text/vnd.turbo-stream.html")
        expect(response.body).to include('action="replace"')
        expect(response.body).to include("conversation_row_#{conversation.uuid}")
      end

      it "updates the title" do
        patch conversation_path(uuid: conversation.uuid),
              params: { title: "New Title" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(conversation.reload.title).to eq("New Title")
      end

      it "does NOT change the draft" do
        conversation.update!(draft: "my draft")

        patch conversation_path(uuid: conversation.uuid),
              params: { title: "New Title" },
              headers: { "Accept" => "text/vnd.turbo-stream.html" }

        expect(conversation.reload.draft).to eq("my draft")
      end
    end
  end

  # ── Unauthenticated ────────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "redirects to root for a draft save" do
      patch conversation_path(uuid: conversation.uuid),
            params: { draft: "hi" }

      expect(response).to have_http_status(:redirect)
      expect(response).to redirect_to(root_path)
    end

    it "does not persist the draft" do
      patch conversation_path(uuid: conversation.uuid),
            params: { draft: "hi" }

      expect(conversation.reload.draft).to be_nil
    end
  end
end
