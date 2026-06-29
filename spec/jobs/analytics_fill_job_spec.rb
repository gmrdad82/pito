# frozen_string_literal: true

require "rails_helper"

RSpec.describe AnalyticsFillJob, type: :job do
  # The glance now also fetches day-series for its 4 charted metrics; stub it so
  # the request flow never hits YouTube (covered on its own in glance_series_spec).
  before { allow(Pito::Analytics::GlanceSeries).to receive(:for).and_return({}) }

  let(:conversation) { Conversation.singleton }

  let!(:channel) { create(:channel, :on_connection) }
  let!(:video)   { create(:video, channel: channel, title: "Boss Fight") }

  let!(:turn) do
    conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "show video #{video.id}"
    )
  end

  # The analytics pending event emitted by the Show handler.
  let!(:analytics_event) do
    Event.create_with_position!(
      conversation: conversation,
      turn:         turn,
      kind:         :enhanced,
      payload:      Pito::MessageBuilder::Analytics::Enhanced.pending(video, period: "28d")
    )
  end

  # The per-message thinking indicator linked to the analytics card (the
  # Finalizer stamps for_event_id; AnalyticsFillJob resolves THIS one by id).
  let!(:thinking_event) do
    Event.create_with_position!(
      conversation: conversation,
      turn:         turn,
      kind:         :thinking,
      payload:      {
        "dictionary"   => "chat",
        "order"        => [ 0, 1, 2 ],
        "started_at"   => 5.seconds.ago.iso8601,
        "for_event_id" => analytics_event.id
      }
    )
  end

  # Canonical full-metrics Result returned by the stub.
  let(:scalars_result) do
    Pito::Analytics::Scalars::Result.new(
      metrics: {
        views:             { current: 1234, previous: 1000 },
        watched_hours:     { current: 12.5, previous: 10.0 },
        avg_view_duration: { current: 245,  previous: 200 },
        avg_viewed_pct:    { current: 38.2, previous: 40.0 },
        subs_gained:       { current: 20,   previous: 10 },
        subs_lost:         { current: 9,    previous: 4 },
        likes:             { current: 210,  previous: 180 },
        dislikes:          { current: 4,    previous: 2 },
        comments:          { current: 31,   previous: 30 }
      },
      label:      "28d",
      comparable: true
    )
  end

  # ── Happy path: scalars available ────────────────────────────────────────────

  context "when Scalars.for returns a Result" do
    before do
      allow(Pito::Analytics::Scalars).to receive(:for).and_return(scalars_result)
    end

    it "rewrites the event payload to status 'ready'" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload.dig("analytics", "status")).to eq("ready")
    end

    it "body of the ready payload includes the scalars table" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload["body"]).to include("pito-analytics-scalars")
    end

    it "does NOT include the unavailable note in the body" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload["body"]).not_to include("pito-analytics-enhanced__note")
    end

    it "preserves the scope_type in the ready marker" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload.dig("analytics", "scope_type")).to eq("Video")
    end

    it "resolves the thinking event (resolved: true in payload)" do
      described_class.perform_now(turn.id)
      expect(thinking_event.reload.payload["resolved"]).to be(true)
    end

    it "stamps elapsed_seconds on the thinking event" do
      described_class.perform_now(turn.id)
      expect(thinking_event.reload.payload["elapsed_seconds"]).to be_a(Numeric)
    end

    it "stamps completed_at on the turn" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Sad path: scalars unavailable ─────────────────────────────────────────────

  context "when Scalars.for returns :unavailable" do
    before do
      allow(Pito::Analytics::Scalars).to receive(:for).and_return(Pito::Analytics::Scalars::UNAVAILABLE)
    end

    it "rewrites the event payload to status 'ready' (not stuck at pending)" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload.dig("analytics", "status")).to eq("ready")
    end

    it "body of the ready payload includes the unavailable note" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload["body"]).to include("pito-analytics-enhanced__note")
    end

    it "does NOT include the scalars table in the body" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload["body"]).not_to include("pito-analytics-scalars")
    end

    it "still resolves the thinking event" do
      described_class.perform_now(turn.id)
      expect(thinking_event.reload.payload["resolved"]).to be(true)
    end

    it "still stamps completed_at on the turn" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Error path: Scalars.for raises ───────────────────────────────────────────

  context "when Scalars.for raises a StandardError" do
    before do
      allow(Pito::Analytics::Scalars).to receive(:for).and_raise(RuntimeError, "API timeout")
    end

    it "writes the unavailable ready state instead of leaving the event pending" do
      described_class.perform_now(turn.id)
      expect(analytics_event.reload.payload.dig("analytics", "status")).to eq("ready")
      expect(analytics_event.reload.payload["body"]).to include("pito-analytics-enhanced__note")
    end

    it "still resolves the thinking event (ensure block runs)" do
      described_class.perform_now(turn.id)
      expect(thinking_event.reload.payload["resolved"]).to be(true)
    end

    it "still stamps completed_at on the turn (ensure block runs)" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Per-message indicator resolution + completion gate ───────────────────────

  context "with a multi-message turn (plain message + pending analytics card)" do
    before do
      allow(Pito::Analytics::Scalars).to receive(:for).and_return(scalars_result)
    end

    # A plain :system message whose own indicator is ALREADY resolved (the
    # Finalizer resolves ready messages before enqueueing this job).
    let!(:plain_message) do
      Event.create_with_position!(
        conversation:, turn:, kind: :system, payload: { "text" => "intro" }
      )
    end
    let!(:plain_indicator) do
      Event.create_with_position!(
        conversation:, turn:, kind: :thinking,
        payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 5.seconds.ago.iso8601,
                   "for_event_id" => plain_message.id, "resolved" => true, "elapsed_seconds" => 1 }
      )
    end

    it "resolves the analytics card's OWN indicator (by for_event_id), leaving others intact" do
      described_class.perform_now(turn.id)
      expect(thinking_event.reload.payload["resolved"]).to be(true)
    end

    it "leaves the already-resolved plain indicator untouched" do
      expect { described_class.perform_now(turn.id) }
        .not_to change { plain_indicator.reload.payload["elapsed_seconds"] }
    end

    it "completes the turn once every indicator is resolved" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end

    it "does NOT complete the turn while another indicator is still spinning" do
      # An unrelated, still-spinning indicator (no matching analytics event) keeps
      # the turn open even after the analytics fill resolves its own indicator.
      Event.create_with_position!(
        conversation:, turn:, kind: :thinking,
        payload: { "dictionary" => "chat", "order" => [ 0 ], "started_at" => 1.second.ago.iso8601,
                   "for_event_id" => -1 }
      )
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).to be_nil
    end
  end

  # ── Missing turn guard ───────────────────────────────────────────────────────

  context "when the turn no longer exists" do
    it "does not raise" do
      expect {
        described_class.perform_now(0)
      }.not_to raise_error
    end
  end
end
