# frozen_string_literal: true

require "rails_helper"

# Persisted-Event-level parity contract for the unified Pito::Dispatch::Finalizer.
#
# The SAME verb reached via the typed pipeline (ChatDispatchJob) and via a
# `#<handle>` reply (FollowUpDispatchJob) must persist IDENTICAL Event kinds and
# the same payload shape. This locks the four chat-vs-reply divergences the
# finalizer unification closed:
#
#   D1 — reply-appended events get the same :system/:enhanced canonicalisation.
#   D6/D7/D8 — period / viewport_width / channel reach the Router on reply.
RSpec.describe "Dispatch pipeline parity (Finalizer)", type: :job do
  let(:conversation) { create(:conversation) }
  let!(:game)        { create(:game, title: "Dead Space") }

  # ── Typed pipeline: drive ChatDispatchJob for `show <game>` ─────────────────
  def chat_result_events
    turn = conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "show game #{game.id}"
    )
    Event.create_with_position!(
      conversation:, turn:, kind: :echo, payload: { text: "show game #{game.id}" }
    )
    ChatDispatchJob.perform_now(turn.id, channel: "@all", authenticated: true)
    turn.events.reload.where.not(kind: %w[echo thinking]).order(:position).to_a
  end

  # ── Reply pipeline: drive FollowUpDispatchJob for the same verb ─────────────
  def reply_result_events
    source_turn = conversation.turns.create!(
      position: Turn.next_position_for(conversation), input_kind: :chat, input_text: "list games"
    )
    source_event = Event.create_with_position!(
      conversation:, turn: source_turn, kind: "system",
      payload: { "reply_handle" => "dead-0001", "reply_target" => "game_list" }
    )
    echo_turn = conversation.turns.create!(
      position: Turn.next_position_for(conversation), input_kind: :hashtag,
      input_text: "#dead-0001 show #{game.id}"
    )
    Event.create_with_position!(
      conversation:, turn: echo_turn, kind: :echo, payload: { text: "#dead-0001 show #{game.id}" }
    )
    FollowUpDispatchJob.perform_now(
      source_event.id, rest: "show #{game.id}", turn_id: echo_turn.id, channel: "@all"
    )
    echo_turn.events.reload.where.not(kind: %w[echo thinking]).order(:position).to_a
  end

  describe "D1 — persisted kinds + payload shape parity for `show <game>`" do
    it "persists the same Event kinds via both pipelines" do
      chat  = chat_result_events
      reply = reply_result_events

      # Bare show → the detail card ONLY (plan-0.9.5 D3 segment selection);
      # both pipelines must agree.
      expect(chat.map(&:kind)).to eq(%w[system])
      expect(reply.map(&:kind)).to eq(chat.map(&:kind))
    end

    it "persists the same detail-card payload shape (same game, same keys)" do
      chat_detail  = chat_result_events.first
      reply_detail = reply_result_events.first

      expect(reply_detail.payload["game_id"]).to eq(game.id).and eq(chat_detail.payload["game_id"])
      # Same structural payload keys (modulo the per-message random reply_handle).
      ignore = %w[reply_handle]
      expect(reply_detail.payload.keys.sort - ignore).to eq(chat_detail.payload.keys.sort - ignore)
    end
  end

  describe "D6/D7/D8 — period / viewport_width / channel reach the dispatcher on reply" do
    it "threads all three kwargs from the job through to the Router.call" do
      source_turn = conversation.turns.create!(
        position: Turn.next_position_for(conversation), input_kind: :chat, input_text: "list games"
      )
      source_event = Event.create_with_position!(
        conversation:, turn: source_turn, kind: "system",
        payload: { "reply_handle" => "dead-0002", "reply_target" => "game_list" }
      )
      echo_turn = conversation.turns.create!(
        position: Turn.next_position_for(conversation), input_kind: :hashtag,
        input_text: "#dead-0002 show #{game.id}"
      )

      expect(Pito::Dispatch::Router).to receive(:call).with(
        hash_including(period: "28d", viewport_width: "1024", channel: "@xyz")
      ).and_return(Pito::Chat::Result::Ok.new(events: [ { kind: :system, payload: { "text" => "ok" } } ]))

      FollowUpDispatchJob.perform_now(
        source_event.id, rest: "show #{game.id}", turn_id: echo_turn.id,
        period: "28d", viewport_width: "1024", channel: "@xyz"
      )
    end
  end
end
