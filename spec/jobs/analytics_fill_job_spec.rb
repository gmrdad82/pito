# frozen_string_literal: true

require "rails_helper"

# AnalyticsFillJob is now a PURE FAN-OUT point: for each pending glance event it
# enqueues one AnalyticsMetricJob per metric (each makes its own dedicated request
# and swaps its own cell). The fill/resolve/complete behaviour lives in
# AnalyticsMetricJob (see analytics_metric_job_spec) — here we assert the fan-out
# itself plus the end-to-end result when the fanned jobs run inline.
RSpec.describe AnalyticsFillJob, type: :job do
  include ActiveJob::TestHelper

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

  let!(:analytics_event) do
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
        "for_event_id" => analytics_event.id
      }
    )
  end

  let(:metric_keys) { Pito::Analytics::ScalarsTableComponent::GLANCE_METRICS.map { |m| m[:key].to_s } }

  # ── Fan-out ──────────────────────────────────────────────────────────────────

  describe "fan-out" do
    it "enqueues one AnalyticsMetricJob per glance metric" do
      expect { described_class.perform_now(turn.id) }
        .to have_enqueued_job(AnalyticsMetricJob).exactly(metric_keys.size).times
    end

    it "enqueues a job per metric key, all scoped to the pending event" do
      described_class.perform_now(turn.id)
      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == AnalyticsMetricJob }
      expect(jobs.map { |j| j[:args][1] }).to match_array(metric_keys)
      expect(jobs.map { |j| j[:args][0] }).to all(eq(analytics_event.id))
    end

    it "does NOT complete the turn itself — the last metric job does" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).to be_nil
    end
  end

  # ── No metrics to fan ─────────────────────────────────────────────────────────

  context "when a pending glance carries no metric_keys" do
    before do
      analytics_event.update!(
        payload: analytics_event.payload.deep_merge("analytics" => { "metric_keys" => [] })
      )
    end

    it "resolves that message's indicator immediately and completes the turn" do
      described_class.perform_now(turn.id)
      expect(thinking_event.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── End-to-end: fanned metric jobs run inline ────────────────────────────────

  context "when the fanned metric jobs run" do
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
        series: {}
      )
    end

    before { allow(Pito::Analytics::MetricFill).to receive(:for).and_return(cell) }

    it "fills the event to ready with the scalars table, resolves the indicator, completes the turn" do
      perform_enqueued_jobs { described_class.perform_now(turn.id) }

      expect(analytics_event.reload.payload.dig("analytics", "status")).to eq("ready")
      expect(analytics_event.payload["body"]).to include("pito-analytics-scalars")
      expect(thinking_event.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Missing turn guard ───────────────────────────────────────────────────────

  context "when the turn no longer exists" do
    it "does not raise" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end
  end
end
