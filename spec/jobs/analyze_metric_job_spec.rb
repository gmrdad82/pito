# frozen_string_literal: true

require "rails_helper"

# AnalyzeMetricJob fills ONE analyze metric cell via its own dedicated request
# (stubbed here through Pito::Analytics::AnalyzeMetricFill), swaps that cell, and
# runs the barrier: the last metric to land per event rewrites the message to ready,
# resolves the indicator, and completes the turn.
#
# AnalyzePrepareJob.aggregate is also stubbed to avoid network — it is called by
# the last metric job to rebuild the aggregate state before writing the ready payload.
RSpec.describe AnalyzeMetricJob, type: :job do
  let(:conversation) { Conversation.singleton }
  let!(:channel)     { create(:channel, :on_connection) }

  let!(:turn) do
    conversation.turns.create!(
      position:   Turn.next_position_for(conversation),
      input_kind: :chat,
      input_text: "analyze channel"
    )
  end

  let!(:event) do
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
        "for_event_id" => event.id
      }
    )
  end

  let(:metric_keys) do
    Pito::Analytics::MetricOrder.for(role: :system, level: :channel).map(&:to_s)
  end

  # Stub the per-metric fill (no network) and the aggregate (no network).
  before do
    allow(Pito::Analytics::AnalyzeMetricFill).to receive(:for)
      .and_return({ no_data: true, caption: "n/a" })
    allow(AnalyzePrepareJob).to receive(:aggregate)
      .and_return({ scaffold: {}, charts: {}, likes: nil, bars: {} })
  end

  # ── Barrier ──────────────────────────────────────────────────────────────────

  describe "the barrier" do
    it "keeps the event pending until every metric has landed" do
      metric_keys[0..-2].each { |k| described_class.perform_now(event.id, k) }

      expect(event.reload.payload.dig("analyze", "status")).to eq("pending")
      expect(thinking_event.reload.payload["resolved"]).to be_nil
      expect(turn.reload.completed_at).to be_nil
    end

    it "records each landed metric in metrics_done" do
      described_class.perform_now(event.id, metric_keys.first)
      expect(event.reload.payload.dig("analyze", "metrics_done")).to eq([ metric_keys.first ])
    end

    it "rewrites to ready, resolves the indicator, and completes the turn once all land" do
      metric_keys.each { |k| described_class.perform_now(event.id, k) }

      expect(event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(event.payload["body"]).to include("pito-analytics-scalars")
      expect(thinking_event.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end

    it "metrics_done de-duplicates duplicate arrivals (idempotent per metric)" do
      2.times { described_class.perform_now(event.id, metric_keys.first) }
      expect(event.reload.payload.dig("analyze", "metrics_done")).to eq([ metric_keys.first ])
    end
  end

  # ── Fault isolation ──────────────────────────────────────────────────────────

  context "when one metric's fill returns no_data" do
    before do
      # Most metrics return a plain no_data cell; one explicitly triggers the
      # no_data path to confirm it does not block the barrier.
      allow(Pito::Analytics::AnalyzeMetricFill).to receive(:for)
        .and_return({ no_data: true, caption: "n/a" })
      allow(Pito::Analytics::AnalyzeMetricFill).to receive(:for)
        .with(hash_including(metric: metric_keys.first))
        .and_return({ no_data: true, caption: metric_keys.first })
    end

    it "still reaches ready (the no_data cell does not block the barrier)" do
      metric_keys.each { |k| described_class.perform_now(event.id, k) }
      expect(event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Guards ───────────────────────────────────────────────────────────────────

  it "no-ops on an already-ready event" do
    event.update!(payload: event.payload.deep_merge("analyze" => { "status" => "ready" }))
    expect { described_class.perform_now(event.id, metric_keys.first) }
      .not_to change { event.reload.payload.dig("analyze", "status") }
  end

  it "does not raise when the event no longer exists" do
    expect { described_class.perform_now(0, metric_keys.first) }.not_to raise_error
  end
end
