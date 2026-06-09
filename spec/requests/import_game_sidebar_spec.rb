# frozen_string_literal: true

require "rails_helper"

# Free-chat `import game[s] [title]` opens the IGDB import sidebar
# (Turbo Stream update to #pito-sidebar), identical to `/games import [title]`.

RSpec.describe "POST /chat import game free-chat fast-path", type: :request do
  let!(:conversation) { Conversation.create! }

  def authenticate_via_totp
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    totp = ROTP::TOTP.new(seed)
    post chat_path, params: { input: "/login #{totp.now}", uuid: conversation.uuid }
    conversation.events.destroy_all
  end

  # ── Authenticated path ────────────────────────────────────────────────────────

  describe "when authenticated" do
    before { authenticate_via_totp }

    it "returns 200 OK for 'import game'" do
      post chat_path, params: { input: "import game", uuid: conversation.uuid }
      expect(response).to have_http_status(:ok)
    end

    it "responds with a Turbo Stream content type" do
      post chat_path, params: { input: "import game", uuid: conversation.uuid }
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
    end

    it "returns a turbo-stream targeting pito-sidebar" do
      post chat_path, params: { input: "import game", uuid: conversation.uuid }
      expect(response.body).to include('target="pito-sidebar"')
    end

    it "wraps the import UI in the Sidebar shell (aside element)" do
      post chat_path, params: { input: "import game", uuid: conversation.uuid }
      expect(response.body).to include("<aside")
    end

    it "does NOT enqueue a ChatDispatchJob" do
      expect {
        post chat_path, params: { input: "import game", uuid: conversation.uuid }
      }.not_to have_enqueued_job(ChatDispatchJob)
    end

    it "does NOT create a Turn" do
      expect {
        post chat_path, params: { input: "import game", uuid: conversation.uuid }
      }.not_to change(Turn, :count)
    end

    it "prefills the search box with the title following 'import game'" do
      post chat_path, params: { input: "import game Hollow Knight", uuid: conversation.uuid }
      expect(response.body).to include("Hollow Knight")
    end

    it "also matches 'import games'" do
      post chat_path, params: { input: "import games", uuid: conversation.uuid }
      expect(response.content_type).to include("text/vnd.turbo-stream.html")
      expect(response.body).to include('target="pito-sidebar"')
    end

    it "is case-insensitive (IMPORT GAME)" do
      post chat_path, params: { input: "IMPORT GAME Hollow Knight", uuid: conversation.uuid }
      expect(response.body).to include('target="pito-sidebar"')
      expect(response.body).to include("Hollow Knight")
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "returns 204 No Content" do
      post chat_path, params: { input: "import game", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT return a Turbo Stream targeting pito-sidebar" do
      post chat_path, params: { input: "import game", uuid: conversation.uuid }
      expect(response.body).not_to include('target="pito-sidebar"')
    end

    it "broadcasts a mandatory-auth error event" do
      post chat_path, params: { input: "import game", uuid: conversation.uuid }
      error_event = conversation.events.where(kind: :error).last
      expect(error_event).to be_present
    end
  end
end
