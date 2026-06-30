# frozen_string_literal: true

require "rails_helper"

# AnalyzePrepareJob is now a PURE FAN-OUT point: for each pending analyze event
# it enqueues one AnalyzeMetricJob per metric key. The fill/resolve/complete
# behaviour lives in AnalyzeMetricJob (see analyze_metric_job_spec.rb) — here we
# assert the fan-out shape, the blank-metric_keys fast-path, and the missing-turn
# guard. An end-to-end pass runs the fanned jobs inline and confirms the final
# ready state lands.
#
# .aggregate is exercised here too (it is now a public class-method re-used by
# the last AnalyzeMetricJob; stub the analytics services to keep it offline).
RSpec.describe AnalyzePrepareJob, type: :job do
  include ActiveJob::TestHelper

  let(:conversation) { Conversation.singleton }
  let!(:channel)     { create(:channel, :on_connection) }

  let!(:turn) do
    conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "analyze channel"
    )
  end

  let!(:analyze_event) do
    Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :system,
      payload: Pito::MessageBuilder::Analyze::Message.pending(
        role: "system", title: "My Channel", level: :channel,
        entity_ids: [ channel.id ], period: "7d",
        conversation: conversation
      )
    )
  end

  let!(:thinking_event) do
    Event.create_with_position!(
      conversation: conversation, turn: turn, kind: :thinking,
      payload: {
        "dictionary"   => "chat",
        "order"        => [ 0, 1, 2 ],
        "started_at"   => 5.seconds.ago.iso8601,
        "for_event_id" => analyze_event.id
      }
    )
  end

  let(:metric_keys) do
    Pito::Analytics::MetricOrder.for(role: :system, level: :channel).map(&:to_s)
  end

  # ── Fan-out ──────────────────────────────────────────────────────────────────

  describe "fan-out" do
    it "enqueues one AnalyzeMetricJob per metric_key" do
      expect { described_class.perform_now(turn.id) }
        .to have_enqueued_job(AnalyzeMetricJob).exactly(metric_keys.size).times
    end

    it "enqueues each job with the event id + the metric key string" do
      described_class.perform_now(turn.id)
      jobs = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == AnalyzeMetricJob }
      expect(jobs.map { |j| j[:args][1] }).to match_array(metric_keys)
      expect(jobs.map { |j| j[:args][0] }).to all(eq(analyze_event.id))
    end

    it "does NOT complete the turn itself — the last metric job does" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).to be_nil
    end
  end

  # ── Multiple pending events (system + enhanced) ───────────────────────────────

  context "with two pending analyze events (system + enhanced)" do
    let!(:enhanced_event) do
      Event.create_with_position!(
        conversation: conversation, turn: turn, kind: :enhanced,
        payload: Pito::MessageBuilder::Analyze::Message.pending(
          role: "enhanced", title: "My Channel", level: :channel,
          entity_ids: [ channel.id ], period: "lifetime",
          conversation: conversation
        )
      )
    end

    let(:enhanced_keys) do
      Pito::Analytics::MetricOrder.for(role: :enhanced, level: :channel).map(&:to_s)
    end

    it "fans out jobs for both events combined" do
      total = metric_keys.size + enhanced_keys.size
      expect { described_class.perform_now(turn.id) }
        .to have_enqueued_job(AnalyzeMetricJob).exactly(total).times
    end

    it "each event's jobs carry its own event id and metric keys" do
      described_class.perform_now(turn.id)
      jobs          = ActiveJob::Base.queue_adapter.enqueued_jobs.select { |j| j[:job] == AnalyzeMetricJob }
      system_jobs   = jobs.select { |j| j[:args][0] == analyze_event.id }
      enhanced_jobs = jobs.select { |j| j[:args][0] == enhanced_event.id }
      expect(system_jobs.map   { |j| j[:args][1] }).to match_array(metric_keys)
      expect(enhanced_jobs.map { |j| j[:args][1] }).to match_array(enhanced_keys)
    end
  end

  # ── No metrics to fan (blank metric_keys fast-path) ──────────────────────────

  context "when a pending analyze event carries blank metric_keys" do
    before do
      analyze_event.update!(
        payload: analyze_event.payload.deep_merge("analyze" => { "metric_keys" => [] })
      )
    end

    it "resolves that message's indicator immediately" do
      described_class.perform_now(turn.id)
      expect(thinking_event.reload.payload["resolved"]).to be(true)
    end

    it "completes the turn (nothing was fanned and all indicators are resolved)" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── End-to-end: fanned metric jobs run inline ─────────────────────────────────

  context "when the fanned metric jobs run" do
    before do
      allow(Pito::Analytics::AnalyzeMetricFill).to receive(:for)
        .and_return({ no_data: true, caption: "n/a" })
      allow(AnalyzePrepareJob).to receive(:aggregate)
        .and_return({ scaffold: {}, charts: {}, likes: nil, bars: {} })
    end

    it "fills the event to ready, resolves the indicator, completes the turn" do
      perform_enqueued_jobs { described_class.perform_now(turn.id) }

      expect(analyze_event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(analyze_event.payload["body"]).to include("pito-analytics-scalars")
      expect(thinking_event.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── .aggregate class method ──────────────────────────────────────────────────

  describe ".aggregate" do
    before do
      allow(Pito::Analytics::Scaffold).to receive(:for).and_return({})
      allow(Pito::Analytics::LikesHearts).to receive(:for).and_return(nil)
      allow(Pito::Analytics::Breakdown).to receive(:for).and_return([])
      allow(Pito::Analytics::Thresholds).to receive(:subs_for).and_return(0)
      allow(Pito::Analytics::DailySeries).to receive(:for).and_return(
        Pito::Analytics::DailySeries::Result.new(dates: [], series: [], total: 0)
      )
      # avg_view_duration / avg_viewed_pct charts go through these (not DailySeries);
      # WebMock's NetConnect error is an Exception (not StandardError), so an
      # unstubbed call would escape compute's rescue and raise.
      allow(Pito::Analytics::AdaptiveSeries).to receive(:for).and_return(
        Pito::Analytics::AdaptiveSeries::Result.new(series: [], total: 0, dates: [])
      )
      allow(Pito::Analytics::RetentionSeries).to receive(:for).and_return(
        Pito::Analytics::RetentionSeries::Result.new(series: [], total_pct: 0, rel_performance: nil)
      )
    end

    it "returns a hash with :scaffold, :charts, :likes, :bars keys" do
      marker = analyze_event.payload["analyze"]
      result = described_class.aggregate(marker)
      expect(result).to include(:scaffold, :charts, :likes, :bars)
    end
  end

  # ── Missing turn guard ───────────────────────────────────────────────────────

  context "when the turn no longer exists" do
    it "does not raise" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end
  end
end
