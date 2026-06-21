# frozen_string_literal: true

require "rails_helper"

# `show vid` / `show vids` / `show video` / `show videos` with no title/id
# opens the videos picker sidebar (Turbo Stream update to #pito-sidebar).
# A command with a title/id falls through to the async pipeline normally.

RSpec.describe "POST /chat video picker fast-path", type: :request do
  let!(:conversation) { Conversation.create! }
  let!(:channel)      { create(:channel, handle: "gmrdad82") }
  let!(:my_vid)       { create(:video, title: "Lies of P Playthrough", channel: channel) }

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

    %w[show\ vid show\ vids show\ video show\ videos].each do |cmd|
      it "returns a Turbo Stream for '#{cmd}'" do
        post chat_path, params: { input: cmd, uuid: conversation.uuid }
        expect(response.content_type).to include("text/vnd.turbo-stream.html")
        expect(response.body).to include('target="pito-sidebar"')
      end
    end

    it "returns 200 OK for bare 'show vid'" do
      post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      expect(response).to have_http_status(:ok)
    end

    it "wraps the video list in the Sidebar shell (aside element)" do
      post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      expect(response.body).to include("<aside")
    end

    it "includes .pito-video-row elements for existing videos" do
      post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      expect(response.body).to include("pito-video-row")
      expect(response.body).to include(my_vid.title)
    end

    it "mounts the pito--videos-nav stimulus controller" do
      post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      expect(response.body).to include("pito--videos-nav")
    end

    it "does NOT enqueue a ChatDispatchJob" do
      expect {
        post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      }.not_to have_enqueued_job(ChatDispatchJob)
    end

    it "does NOT create a Turn" do
      expect {
        post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      }.not_to change(Turn, :count)
    end

    it "dispatches 'show vid Lies of P' (with title) through the async pipeline" do
      expect {
        post chat_path, params: { input: "show vid Lies of P", uuid: conversation.uuid }
      }.to have_enqueued_job(ChatDispatchJob)
    end

    it "dispatches 'show vid #1' (with id) through the async pipeline" do
      expect {
        post chat_path, params: { input: "show vid ##{my_vid.id}", uuid: conversation.uuid }
      }.to have_enqueued_job(ChatDispatchJob)
    end
  end

  # ── Unauthenticated path ─────────────────────────────────────────────────────

  describe "when unauthenticated" do
    it "returns 204 No Content for bare 'show vid'" do
      post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      expect(response).to have_http_status(:no_content)
    end

    it "does NOT return a Turbo Stream targeting pito-sidebar" do
      post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      expect(response.body).not_to include('target="pito-sidebar"')
    end

    it "broadcasts a mandatory-auth error event" do
      post chat_path, params: { input: "show vid", uuid: conversation.uuid }
      error_event = conversation.events.where(kind: :error).last
      expect(error_event).to be_present
    end
  end
end
