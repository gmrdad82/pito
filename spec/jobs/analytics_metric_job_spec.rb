# frozen_string_literal: true

require "rails_helper"

# AnalyticsMetricJob fills ONE metric cell via its own dedicated request (stubbed
# here through Pito::Analytics::MetricFill), swaps that cell, and runs the barrier:
# the last metric to land per event rewrites the message to ready, resolves the
# indicator, and completes the turn.
RSpec.describe AnalyticsMetricJob, type: :job do
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

  let!(:event) do
    Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :enhanced,
      payload: Pito::MessageBuilder::Analytics::Enhanced.pending(video, period: "28d")
    )
  end

  let!(:thinking_event) do
    Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :thinking,
      payload: {
        "dictionary"   => "chat",
        "order"        => [ 0, 1, 2 ],
        "started_at"   => 5.seconds.ago.iso8601,
        "for_event_id" => event.id
      }
    )
  end

  let(:keys) { Pito::Analytics::ScalarsTableComponent::GLANCE_METRICS.map { |m| m[:key].to_s } }

  let(:cell) do
    Pito::Analytics::MetricFill::Cell.new(
      result: Pito::Analytics::Scalars::Result.new(
        metrics: {
          views:             { current: 1234, previous: nil },
          watched_hours:     { current: 12.5, previous: nil },
          avg_view_duration: { current: 245,  previous: nil },
          subs_gained:       { current: 20,   previous: nil },
          subs_lost:         { current: 9,    previous: nil },
          likes:             { current: 210,  previous: nil },
          dislikes:          { current: 4,    previous: nil }
        },
        label: "lifetime", comparable: false
      ),
      series: { views: [ 1, 2, 3 ] }
    )
  end

  before { allow(Pito::Analytics::MetricFill).to receive(:for).and_return(cell) }

  # ── Barrier ──────────────────────────────────────────────────────────────────

  describe "the barrier" do
    it "keeps the event pending until every metric has landed" do
      keys[0..-2].each { |k| described_class.perform_now(event.id, k) }

      expect(event.reload.payload.dig("analytics", "status")).to eq("pending")
      expect(thinking_event.reload.payload["resolved"]).to be_nil
      expect(turn.reload.completed_at).to be_nil
    end

    it "records each landed metric in metrics_done" do
      described_class.perform_now(event.id, keys.first)
      expect(event.reload.payload.dig("analytics", "metrics_done")).to eq([ keys.first ])
    end

    it "rewrites to ready, resolves the indicator, and completes the turn once all land" do
      keys.each { |k| described_class.perform_now(event.id, k) }

      expect(event.reload.payload.dig("analytics", "status")).to eq("ready")
      expect(event.payload["body"]).to include("pito-analytics-scalars")
      expect(thinking_event.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Fault isolation ──────────────────────────────────────────────────────────

  context "when one metric's dedicated request is unavailable" do
    before do
      allow(Pito::Analytics::MetricFill).to receive(:for).and_return(cell)
      allow(Pito::Analytics::MetricFill).to receive(:for)
        .with(hash_including(key: keys.first)).and_return(Pito::Analytics::MetricFill::UNAVAILABLE)
    end

    it "still reaches ready (the failed metric does not block the others)" do
      keys.each { |k| described_class.perform_now(event.id, k) }
      expect(event.reload.payload.dig("analytics", "status")).to eq("ready")
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Guards ───────────────────────────────────────────────────────────────────

  it "no-ops on an already-ready event" do
    event.update!(payload: event.payload.deep_merge("analytics" => { "status" => "ready" }))
    expect { described_class.perform_now(event.id, keys.first) }
      .not_to change { event.reload.payload.dig("analytics", "status") }
  end

  it "does not raise when the event no longer exists" do
    expect { described_class.perform_now(0, keys.first) }.not_to raise_error
  end
end
