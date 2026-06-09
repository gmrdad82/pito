# frozen_string_literal: true

require "rails_helper"

RSpec.describe "Conversation requests", type: :request do
  # ── Channel-filter token sanity (Bug: @@handle double-prefix) ───────────────
  # set_channels builds @channels for every HTML request.  When a Channel's
  # handle is stored with a leading "@" (the normal case), the old
  # `"@#{h}"` interpolation produced "@@handle".  at_handle normalises it.
  describe "channel filter tokens rendered with single @" do
    let!(:channel_with_at)    { create(:channel, handle: "@gaming") }
    let!(:channel_without_at) { create(:channel, handle: "esports") }

    before do
      # Authenticate so the filter / channels JSON is rendered into the page.
      seed = ROTP::Base32.random_base32
      AppSetting.enroll_totp!(seed: seed)
      post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }

      get conversation_path(uuid: Conversation.singleton.uuid)
    end

    it "never emits a double-at token (@@) in the channels data attribute" do
      expect(response.body).not_to include("@@")
    end

    it "includes @gaming (single @) in the channels data attribute" do
      # The JSON array is HTML-attribute-escaped: &quot;@gaming&quot;
      expect(response.body).to include("@gaming")
    end

    it "includes @esports (normalised from stored 'esports') in the channels data attribute" do
      expect(response.body).to include("@esports")
    end

    it "includes the @all sentinel in the channels data attribute" do
      expect(response.body).to include("@all")
    end
  end


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

    it "wires the scrollback Stimulus controllers on the scrollback container" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include('data-controller="pito--scrollback pito--quick-run pito--cable-health pito--lasthashtag"')
    end

    it "includes the uuid in the chat form" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include(conversation.uuid)
    end

    it "renders the mini status notification count from real unread notifications" do
      # The notification count only renders for an authenticated session.
      seed = ROTP::Base32.random_base32
      AppSetting.enroll_totp!(seed: seed)
      post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }

      create(:notification)
      create(:notification)
      get conversation_path(uuid: conversation.uuid)
      # 2 unread notifications → "2 notifications" in the mini-status
      expect(response.body).to include("2 notifications")
    end

    it "does not render the notification badge when there are no unread notifications" do
      get conversation_path(uuid: conversation.uuid)
      # No notifications in DB → count = 0 → badge hidden
      expect(response.body).not_to include("ctrl+/")
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

  # ── P58 — Input history data attribute ─────────────────────────────────────
  # The conversation page must embed sent input_text values (newest first) as a
  # JSON array in data-pito--history-entries-value on #pito-chatbox so the
  # history Stimulus controller can restore them with ↑/↓.

  describe "GET /chat/:uuid — history entries attribute" do
    let(:conversation) { create(:conversation) }

    it "renders an empty JSON array when the conversation has no turns" do
      get conversation_path(uuid: conversation.uuid)
      expect(response.body).to include("data-pito--history-entries-value")
      # An empty JSON array encoded as an HTML attribute value.
      expect(response.body).to include("data-pito--history-entries-value=\"[]\"")
    end

    it "includes sent input_text values (newest first) in the history attribute" do
      conversation.turns.create!(position: 1, input_kind: :slash, input_text: "/help")
      conversation.turns.create!(position: 2, input_kind: :chat,  input_text: "what is my top channel?")
      conversation.turns.create!(position: 3, input_kind: :slash, input_text: "/config sound off")

      get conversation_path(uuid: conversation.uuid)

      attr_match = response.body.match(/data-pito--history-entries-value="([^"]*)"/)
      expect(attr_match).not_to be_nil
      raw = CGI.unescapeHTML(attr_match[1])
      parsed = JSON.parse(raw)
      # Newest first
      expect(parsed).to eq([ "/config sound off", "what is my top channel?", "/help" ])
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
