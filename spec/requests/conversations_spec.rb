# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation requests", type: :request do
  describe "GET /chat/:uuid" do
    let(:conversation) { create(:conversation) }

    it "renders the conversation page for a known uuid" do
      get conversation_path(uuid: conversation.uuid)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(conversation.uuid)
    end

    it "returns 404 for an unknown uuid" do
      get conversation_path(uuid: "nonexistent-uuid-1234")
      expect(response).to have_http_status(:not_found)
    end

    it "subscribes to the correct Turbo Stream" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include("<turbo-cable-stream-source")
    end

    it "renders the scrollback container" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include('id="pito-scrollback"')
    end

    it "scrollback padding-bottom provides gap instead of the border-top hack" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include("padding: 32px 50px 20px")
    end

    it "does not use the invisible border-top colour hack" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).not_to include("border-top")
    end

    it "wires the scrollback Stimulus controller on the scrollback container" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include('data-controller="pito--scrollback"')
    end

    it "includes the uuid in the chat form" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include(conversation.uuid)
    end

    it "renders the mini status with notification placeholder (3)" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include("(3)")
    end

    # ── Dots indicator wiring ───────────────────────────────────────────────────
    # The dots wrapper must carry data-controller="pito--dots" so the Stimulus
    # controller can manage visibility (hidden at rest, shown while the backend
    # is processing a command, hidden again once the echo arrives).

    it "renders the dots wrapper with the pito--dots Stimulus controller" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include('data-controller="pito--dots"')
    end

    it "renders the pito-comet inside the dots wrapper" do
      get conversation_path(uuid: conversation.uuid)
      # Both the controller attribute and the comet class must be present.
      expect(response.body).to include('data-controller="pito--dots"')
      expect(response.body).to include('class="pito-comet"')
    end
  end

  # ── Per-turn grouping ───────────────────────────────────────────────────────
  # Events are grouped into #turn_<id> containers so each turn's result stays
  # under its echo regardless of async-job completion order. The show view must
  # reproduce the same grouping the cable broadcasts build live.

  describe "GET /chat/:uuid event grouping" do
    it "wraps each turn's events in a #turn_<id> container, echo before result" do
      conversation = create(:conversation)
      turn_a = conversation.turns.create!(position: 1, input_kind: :chat, input_text: "first")
      turn_b = conversation.turns.create!(position: 2, input_kind: :chat, input_text: "second")
      # Interleaved positions mimic concurrent dispatch: both echoes, then both results.
      conversation.events.create!(turn: turn_a, position: 1, kind: :echo, payload: { text: "first" })
      conversation.events.create!(turn: turn_b, position: 2, kind: :echo, payload: { text: "second" })
      conversation.events.create!(turn: turn_a, position: 3, kind: :system,
                                  payload: { message_key: "pito.chat.list.descriptions.list", message_args: {} })
      conversation.events.create!(turn: turn_b, position: 4, kind: :system,
                                  payload: { message_key: "pito.chat.list.descriptions.list", message_args: {} })

      get conversation_path(uuid: conversation.uuid)

      expect(response.body).to include(%(id="turn_#{turn_a.id}"))
      expect(response.body).to include(%(id="turn_#{turn_b.id}"))
      # turn_a container appears before turn_b container.
      expect(response.body.index(%(id="turn_#{turn_a.id}")))
        .to be < response.body.index(%(id="turn_#{turn_b.id}"))
    end
  end

  # ── Echo-detection contract ─────────────────────────────────────────────────
  # The scrollback MutationObserver (scrollback_controller.js) classifies appended
  # segments by whether they carry `data-accent="purple"` (echo = user command
  # acknowledgement) vs anything else (result).  This spec anchors the server-side
  # HTML contract those class names depend on.

  describe "echo segment HTML contract" do
    it "echo events render a segment bar with data-accent='purple'" do
      conversation = create(:conversation)
      turn = conversation.turns.create!(
        position: 1, input_kind: :slash, input_text: "/help"
      )
      event = conversation.events.create!(
        turn:, position: 1, kind: :echo, payload: { text: "/help" }
      )
      html = Pito::Stream::EventRenderer.render(event)
      expect(html).to include('data-accent="purple"')
    end

    it "non-echo events render a segment bar without data-accent='purple'" do
      conversation = create(:conversation)
      turn = conversation.turns.create!(
        position: 1, input_kind: :slash, input_text: "/help"
      )
      event = conversation.events.create!(
        turn:, position: 2, kind: :error,
        payload: { message_key: "pito.auth.required", message_args: {} }
      )
      html = Pito::Stream::EventRenderer.render(event)
      expect(html).not_to include('data-accent="purple"')
    end
  end
end
