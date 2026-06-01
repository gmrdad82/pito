# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Authentication via /authenticate", type: :request do
  include ActiveJob::TestHelper

  let(:conversation) { Conversation.singleton }
  let(:seed) { ROTP::Base32.random_base32 }
  let(:totp) { ROTP::TOTP.new(seed) }

  before { AppSetting.enroll_totp!(seed: seed) }

  def last_turn_events
    Turn.last_for(conversation).events.order(:position)
  end

  describe "valid code" do
    it "masks the code in the echo and never persists it" do
      post "/chat", params: { input: "/authenticate #{totp.now}", uuid: conversation.uuid }

      echo = last_turn_events.find { |e| e.kind == "echo" }
      expect(echo.payload["text"]).to eq("/authenticate ******")

      # The real code appears nowhere in the DB
      expect(Event.pluck(:payload).to_s).not_to include(totp.now)
      expect(Turn.pluck(:input_text).join).not_to include(totp.now)
    end

    it "emits an authenticated assistant_text event" do
      post "/chat", params: { input: "/authenticate #{totp.now}", uuid: conversation.uuid }

      kinds = last_turn_events.pluck(:kind)
      expect(kinds).to eq(%w[echo assistant_text])
      success = last_turn_events.find { |e| e.kind == "assistant_text" }
      expect(success.payload["message_key"]).to eq("pito.auth.authenticated")
    end

    it "sets the session cookie" do
      post "/chat", params: { input: "/authenticate #{totp.now}", uuid: conversation.uuid }
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_present
    end

    it "lets subsequent commands through" do
      post "/chat", params: { input: "/authenticate #{totp.now}", uuid: conversation.uuid }
      conversation.turns.destroy_all

      post "/chat", params: { input: "/help", uuid: conversation.uuid }
      expect(last_turn_events.pluck(:kind)).to include("echo")
      expect(last_turn_events.none? { |e| e.payload["message_key"] == "pito.auth.required" }).to be true
    end
  end

  describe "invalid code" do
    it "emits an auth failed error and sets no cookie" do
      post "/chat", params: { input: "/authenticate 000000", uuid: conversation.uuid }

      error = last_turn_events.find { |e| e.kind == "error" }
      expect(error.payload["message_key"]).to eq("pito.auth.failed")
      expect(cookies[Pito::Auth::SessionCookie::COOKIE_NAME]).to be_blank
    end
  end

  describe "gating when unauthenticated" do
    # Gating is now applied in ChatDispatchJob (async), so the error event only
    # exists after the job runs. The echo is persisted synchronously by the
    # controller and is present immediately.

    it "refuses a slash command with pito.auth.required (after the job runs)" do
      perform_enqueued_jobs { post "/chat", params: { input: "/help", uuid: conversation.uuid } }

      error = last_turn_events.find { |e| e.kind == "error" }
      expect(error.payload["message_key"]).to eq("pito.auth.required")
    end

    it "refuses a chat message with pito.auth.required (after the job runs)" do
      perform_enqueued_jobs { post "/chat", params: { input: "list videos", uuid: conversation.uuid } }

      error = last_turn_events.find { |e| e.kind == "error" }
      expect(error.payload["message_key"]).to eq("pito.auth.required")
    end

    it "echoes the refused input synchronously (before the job runs)" do
      post "/chat", params: { input: "list videos", uuid: conversation.uuid }

      echo = last_turn_events.find { |e| e.kind == "echo" }
      expect(echo.payload["text"]).to eq("list videos")
    end

    it "enqueues the dispatch job with authenticated: false" do
      expect {
        post "/chat", params: { input: "/help", uuid: conversation.uuid }
      }.to have_enqueued_job(ChatDispatchJob).with(anything, hash_including(authenticated: false))
    end
  end
end
