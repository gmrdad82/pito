# frozen_string_literal: true

require "rails_helper"

# GET /chat/:uuid.json — the scrollback backfill for non-browser clients
# (pito-tui). Same events, same Pito::Stream::EventJson shape the live
# Pito::JsonChannel mirror uses, so backfill and stream can never drift.

RSpec.describe "GET /chat/:uuid.json", type: :request do
  let!(:conversation) { Conversation.create! }

  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  context "when authenticated" do
    before { login! }

    it "returns the conversation envelope and the events in EventJson shape, position-ordered" do
      turn = conversation.turns.create!(
        position: Turn.next_position_for(conversation), input_kind: :chat, input_text: "hello"
      )
      echo = Event.create_with_position!(conversation:, turn:, kind: :echo, payload: { "text" => "hello" })
      sys  = Event.create_with_position!(conversation:, turn:, kind: :system, payload: { "text" => "hi there" })

      get "/chat/#{conversation.uuid}.json"

      expect(response).to have_http_status(:ok)
      body = response.parsed_body
      expect(body["conversation"]["uuid"]).to eq(conversation.uuid)
      expect(body["conversation"]).to have_key("title")
      expect(body["conversation"]["display_name"]).to eq(conversation.display_name)

      # G125: the context meter — server-computed, the exact web-meter numbers.
      ctx = body["conversation"]["context"]
      expect(ctx["count"]).to eq(conversation.context_event_count)
      expect(ctx["threshold"]).to eq(Pito::Shell::ContextMeterComponent::THRESHOLD)
      expect(ctx["pct"]).to eq(Pito::Shell::ContextMeterComponent.pct(conversation.context_event_count))

      # G125: identity + unread for the mini status.
      expect(body["me"]["handle"]).to eq("@#{AppSetting.nickname}")
      expect(body["me"]["name"]).to eq(AppSetting.nickname)
      expect(body["notifications"]["unread"]).to eq(Notification.unread.count)

      expect(body["events"].map { |e| e["id"] }).to eq([ echo.id, sys.id ])
      first = body["events"].first
      expect(first.keys).to match_array(%w[id turn_id kind payload position created_at])
      expect(first["kind"]).to eq("echo")
      expect(first["payload"]).to eq("text" => "hello")
      expect(first["turn_id"]).to eq(turn.id)
    end
  end

  context "when anonymous" do
    # The HTML page withholds the scrollback silently (the visitor still gets
    # the shell to /login in); JSON is explicit about it.
    it "rejects with 401 and the unauthenticated error" do
      get "/chat/#{conversation.uuid}.json"

      expect(response).to have_http_status(:unauthorized)
      expect(response.parsed_body["error"]).to eq("unauthenticated")
      expect(response.parsed_body["message"]).to be_present
    end
  end
end
