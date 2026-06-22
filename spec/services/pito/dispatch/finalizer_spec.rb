# frozen_string_literal: true

require "rails_helper"

# Per-message thinking-indicator mechanism owned by the Finalizer (H5.4):
# every result message gets its OWN indicator that resolves when THAT message is
# ready, the turn completes only when ALL indicators are resolved, and the
# pre-dispatch placeholder is reused for the first message (no no-spinner gap).
RSpec.describe Pito::Dispatch::Finalizer do
  let(:conversation) { Conversation.create! }
  let(:turn) do
    conversation.turns.create!(position: Turn.next_position_for(conversation), input_kind: :chat, input_text: "go")
  end
  let(:finalizer) { described_class.new(conversation:) }

  # The echo + pre-dispatch placeholder the controller emits before the job runs.
  let!(:echo) do
    Event.create_with_position!(conversation:, turn:, kind: :echo, payload: { text: "go" })
  end
  let!(:placeholder) do
    Event.create_with_position!(
      conversation:, turn:, kind: :thinking,
      payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 3.seconds.ago.iso8601 }
    )
  end

  def thinking_events
    turn.events.where(kind: :thinking).order(:position).to_a
  end

  def pending_analytics_payload
    {
      "html"      => true,
      "anchor"    => true,
      "analytics" => { "status" => "pending", "scope_type" => "Video", "scope_id" => 1, "period" => "28d", "intro" => "x" }
    }
  end

  describe "#persist — per-message indicators" do
    it "reuses the pre-dispatch placeholder for the first message (no extra indicator)" do
      finalizer.persist(events: [ { kind: :system, payload: { "text" => "one" } } ], turn:)
      expect(thinking_events.count).to eq(1)
    end

    it "links the first message's indicator to it via for_event_id" do
      message = finalizer.persist(events: [ { kind: :system, payload: { "text" => "one" } } ], turn:).first
      expect(placeholder.reload.payload["for_event_id"]).to eq(message.id)
    end

    it "emits one fresh indicator per additional message, each linked to its message" do
      msgs = finalizer.persist(
        events: [
          { kind: :system, payload: { "text" => "intro" } },
          { kind: :enhanced, payload: { "text" => "card" } }
        ],
        turn:
      )
      links = thinking_events.map { |t| t.payload["for_event_id"] }
      expect(links).to match_array(msgs.map(&:id))
    end

    it "positions every indicator immediately before its linked message (refresh order)" do
      msgs = finalizer.persist(
        events: [
          { kind: :system, payload: { "text" => "intro" } },
          { kind: :enhanced, payload: { "text" => "card" } }
        ],
        turn:
      )
      msgs.each do |message|
        indicator = thinking_events.find { |t| t.payload["for_event_id"] == message.id }
        expect(indicator.position).to be < message.position
      end
    end

    it "emits a fresh indicator for the first message when no placeholder exists" do
      placeholder.destroy!
      finalizer.persist(events: [ { kind: :system, payload: { "text" => "one" } } ], turn:)
      expect(thinking_events.count).to eq(1)
    end
  end

  describe "#complete — ready (non-analytics) turn" do
    it "resolves every indicator and completes the turn" do
      msgs = finalizer.persist(
        events: [ { kind: :system, payload: { "text" => "a" } }, { kind: :enhanced, payload: { "text" => "b" } } ],
        turn:
      )
      finalizer.complete(turn:, events: msgs)

      expect(thinking_events.map { |t| t.payload["resolved"] }).to all(be(true))
      expect(turn.reload.completed_at).not_to be_nil
    end

    it "resolves an orphan placeholder on a zero-result turn so it never spins forever" do
      finalizer.complete(turn:, events: [])
      expect(placeholder.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  describe "#complete — multi-message turn with a pending-analytics card" do
    let(:events) do
      finalizer.persist(
        events: [
          { kind: :system,   payload: { "text" => "intro" } },        # ready
          { kind: :enhanced, payload: { "text" => "card" } },         # ready
          { kind: :enhanced, payload: pending_analytics_payload }     # pending
        ],
        turn:
      )
    end

    it "resolves the ready messages' indicators immediately" do
      finalizer.complete(turn:, events:)
      ready = events.first(2)
      ready.each do |message|
        indicator = thinking_events.find { |t| t.payload["for_event_id"] == message.id }
        expect(indicator.reload.payload["resolved"]).to be(true)
      end
    end

    it "leaves the pending-analytics card's indicator spinning" do
      pending = events.last
      finalizer.complete(turn:, events:)
      indicator = thinking_events.find { |t| t.payload["for_event_id"] == pending.id }
      expect(indicator.reload.payload["resolved"]).to be_nil
    end

    it "does NOT complete the turn (deferred to AnalyticsFillJob)" do
      finalizer.complete(turn:, events:)
      expect(turn.reload.completed_at).to be_nil
    end

    it "enqueues AnalyticsFillJob for the turn" do
      expect { finalizer.complete(turn:, events:) }
        .to have_enqueued_job(AnalyticsFillJob).with(turn.id)
    end
  end

  describe "refresh safety" do
    it "re-renders a resolved indicator (past-tense) and a pending one (spinner) from persisted payload" do
      events = finalizer.persist(
        events: [ { kind: :system, payload: { "text" => "a" } }, { kind: :enhanced, payload: pending_analytics_payload } ],
        turn:
      )
      finalizer.complete(turn:, events:)

      resolved = thinking_events.find { |t| t.payload["for_event_id"] == events.first.id }
      pending  = thinking_events.find { |t| t.payload["for_event_id"] == events.last.id }

      expect(Pito::Stream::EventRenderer.render(resolved.reload)).to include("pito-thinking__message")
      expect(Pito::Stream::EventRenderer.render(pending.reload)).to include("data-controller=\"pito--thinking\"")
    end
  end
end
