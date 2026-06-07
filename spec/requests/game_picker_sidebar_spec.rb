# frozen_string_literal: true

require "rails_helper"

# T10.10 — No-arg `show game` / `rm game` / `delete game` opens the games
# picker sidebar (Turbo Stream update to #pito-sidebar).  A command with a
# title falls through to the async pipeline normally.

RSpec.describe "POST /chat game picker fast-path", type: :request do
  let!(:conversation) { Conversation.create! }
  let!(:lies_of_p)    { create(:game, title: "Lies of P") }

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

    %w[show delete\ game rm\ game delete\ games rm\ games show\ games show\ game].each do |cmd|
      it "returns a Turbo Stream for '#{cmd}'" do
        post chat_path, params: { input: cmd, uuid: conversation.uuid }
        expect(response.content_type).to include("text/vnd.turbo-stream.html")
        expect(response.body).to include('target="pito-sidebar"')
      end
    end

    it "returns 200 OK for bare 'show game'" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      expect(response).to have_http_status(:ok)
    end

    it "wraps the game list in the Sidebar shell (aside element)" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      expect(response.body).to include("<aside")
    end

    it "includes .pito-game-row elements for existing games" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      expect(response.body).to include("pito-game-row")
      expect(response.body).to include(lies_of_p.title)
    end

    it "mounts the pito--games-nav stimulus controller" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      expect(response.body).to include("pito--games-nav")
    end

    it "sets mode 'show' for 'show game'" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      expect(response.body).to include('data-pito--games-nav-mode-value="show"')
    end

    it "sets mode 'delete' for 'rm game'" do
      post chat_path, params: { input: "rm game", uuid: conversation.uuid }
      expect(response.body).to include('data-pito--games-nav-mode-value="delete"')
    end

    it "sets mode 'delete' for 'delete game'" do
      post chat_path, params: { input: "delete game", uuid: conversation.uuid }
      expect(response.body).to include('data-pito--games-nav-mode-value="delete"')
    end

    it "does NOT enqueue a ChatDispatchJob" do
      expect {
        post chat_path, params: { input: "show game", uuid: conversation.uuid }
      }.not_to have_enqueued_job(ChatDispatchJob)
    end

    it "does NOT create a Turn" do
      expect {
        post chat_path, params: { input: "show game", uuid: conversation.uuid }
      }.not_to change(Turn, :count)
    end

    it "dispatches 'show game Lies of P' (with title) through the async pipeline" do
      expect {
        post chat_path, params: { input: "show game Lies of P", uuid: conversation.uuid }
      }.to have_enqueued_job(ChatDispatchJob)
    end

    it "dispatches 'show game #1' (with id) through the async pipeline" do
      expect {
        post chat_path, params: { input: "show game ##{lies_of_p.id}", uuid: conversation.uuid }
      }.to have_enqueued_job(ChatDispatchJob)
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "returns 204 No Content for bare 'show game'" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT return a Turbo Stream targeting pito-sidebar" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      expect(response.body).not_to include('target="pito-sidebar"')
    end

    it "broadcasts a mandatory-auth error event" do
      post chat_path, params: { input: "show game", uuid: conversation.uuid }
      error_event = conversation.events.where(kind: :error).last
      expect(error_event).to be_present
    end
  end
end
