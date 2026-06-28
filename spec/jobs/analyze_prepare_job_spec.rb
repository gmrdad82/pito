# frozen_string_literal: true

require "rails_helper"

# Fills the two pending analyze events (system + enhanced) for a turn, resolves
# each message's per-message thinking indicator, and completes the turn.
#
# The 0/1 scaffold rendering is tested here end-to-end; detailed DOM assertions
# live in spec/components/pito/analytics/scaffold_component_spec.rb.
#
# Scope dispatch:
#   channel level → Scaffold.for receives groups with :channel subject (videos: nil semantics)
#   vid level     → Scaffold.for receives groups with [youtube_video_id] subject
#   game level    → resolves via linked videos, same Scaffold path
#
# Fan-out memoisation: each role gets exactly one Scaffold.for call per job run
# (keyed by level:ids:period:role signature in the job's cache hash).
RSpec.describe AnalyzePrepareJob, type: :job do
  let(:conversation) { Conversation.singleton }

  # Stub all chart-data paths so the :system AreaChart cells render without
  # hitting YouTube. The five chart metrics (views/watched_hours/subs/
  # avg_view_duration/avg_viewed_pct) are bespoke AreaChart cells, NOT 0/1
  # scalar cells — so the "all cells 0/1" assertions count only the remaining
  # scalar metrics (likes/comments/subscribed_status = 3 cells).
  before do
    allow(Pito::Analytics::DailySeries).to receive(:for).and_return(
      Pito::Analytics::DailySeries::Result.new(dates: [], series: [ 1, 2, 3 ], total: 6)
    )
    allow(Pito::Analytics::AdaptiveSeries).to receive(:for).and_return(
      Pito::Analytics::AdaptiveSeries::Result.new(series: [ 90.0, 120.0, 110.0 ], total: 108.0, dates: [])
    )
    allow(Pito::Analytics::RetentionSeries).to receive(:for).and_return(
      Pito::Analytics::RetentionSeries::Result.new(series: [ 95.0, 80.0, 65.0, 50.0 ], total_pct: 72.5, rel_performance: 0.52)
    )
    allow(Pito::Analytics::Thresholds).to receive(:subs_for).and_return(70)
  end

  # Stub Scaffold.for to return a per-role map of metric => data-pulled?.
  # Default: all metrics "true" (every cell renders "1").
  def stub_scaffold(map = nil)
    if map
      allow(Pito::Analytics::Scaffold).to receive(:for).and_return(map)
    else
      allow(Pito::Analytics::Scaffold).to receive(:for) do |role:, level:, **|
        Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
      end
    end
  end

  # Persist a pair of pending analyze events (system + enhanced) for `turn` at
  # `level` with the given `entity_ids`, each linked to its own thinking
  # indicator. Returns [system_event, enhanced_event, system_indicator,
  # enhanced_indicator] so callers can call .reload on each.
  def build_pending_events(turn, level:, entity_ids:, period: "7d")
    events = Pito::MessageBuilder::Analyze::Message::ROLES.map do |role|
      kind    = role == "system" ? :system : :enhanced
      payload = Pito::MessageBuilder::Analyze::Message.pending(
        role: role, title: "Test Scope", level: level,
        entity_ids: entity_ids, period: period, conversation:
      )
      Event.create_with_position!(conversation: conversation, turn: turn, kind: kind, payload: payload)
    end

    indicators = events.map do |event|
      Event.create_with_position!(
        conversation: conversation,
        turn:         turn,
        kind:         :thinking,
        payload: {
          "dictionary"   => "chat",
          "order"        => [ 0 ],
          "started_at"   => 5.seconds.ago.iso8601,
          "for_event_id" => event.id
        }
      )
    end

    events + indicators
  end

  # ── Missing turn guard ─────────────────────────────────────────────────────

  context "when the turn no longer exists" do
    it "does not raise" do
      expect { described_class.perform_now(0) }.not_to raise_error
    end
  end

  # ── Channel level ─────────────────────────────────────────────────────────

  context "channel level: usable channel" do
    let!(:channel) { create(:channel, :on_connection) }

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze channel"
      )
    end

    before do
      @system_event, @enhanced_event, @system_indicator, @enhanced_indicator =
        build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
      stub_scaffold
    end

    it "writes the system event to status 'ready'" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "writes the enhanced event to status 'ready'" do
      described_class.perform_now(turn.id)
      expect(@enhanced_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "body of the ready system event includes the scalars grid" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).to include("pito-analytics-scalars")
    end

    it "body of the ready enhanced event includes the scalars grid" do
      described_class.perform_now(turn.id)
      expect(@enhanced_event.reload.payload["body"]).to include("pito-analytics-scalars")
    end

    it "ready system body has 0/1 cells, not a scalars value table" do
      described_class.perform_now(turn.id)
      body = @system_event.reload.payload["body"]
      doc  = Nokogiri::HTML.fragment(body)
      values = doc.css(".pito-analytics-scalars__value").map(&:text)
      expect(values).not_to be_empty
      expect(values).to all(match(/\A[01]\z/))
    end

    it "body does NOT include the unavailable note (that concept is gone for analyze)" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).not_to include("pito-analytics-enhanced__note")
      expect(@enhanced_event.reload.payload["body"]).not_to include("pito-analytics-enhanced__note")
    end

    it "resolves the system thinking indicator" do
      described_class.perform_now(turn.id)
      expect(@system_indicator.reload.payload["resolved"]).to be(true)
    end

    it "resolves the enhanced thinking indicator" do
      described_class.perform_now(turn.id)
      expect(@enhanced_indicator.reload.payload["resolved"]).to be(true)
    end

    it "stamps elapsed_seconds on both indicators" do
      described_class.perform_now(turn.id)
      expect(@system_indicator.reload.payload["elapsed_seconds"]).to be_a(Numeric)
      expect(@enhanced_indicator.reload.payload["elapsed_seconds"]).to be_a(Numeric)
    end

    it "stamps completed_at on the turn" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end

    it "passes groups with :channel subject to Scaffold.for (channel-wide, not per-video)" do
      captured_subjects = []
      allow(Pito::Analytics::Scaffold).to receive(:for) do |groups:, role:, level:, **|
        captured_subjects.concat(groups.map(&:last))
        Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
      end
      described_class.perform_now(turn.id)
      expect(captured_subjects).not_to be_empty
      expect(captured_subjects).to all(eq(:channel))
    end

    it "persists chart data for views, watched_hours, and subs in the :system marker" do
      described_class.perform_now(turn.id)
      marker = @system_event.reload.payload["analyze"]
      expect(marker["views"]).to be_a(Hash)
      expect(marker["watched_hours"]).to be_a(Hash)
      expect(marker["subs"]).to be_a(Hash)
      # each chart hash carries the expected keys
      %w[views watched_hours subs].each do |key|
        expect(marker[key]).to include("series", "total", "target_daily")
      end
    end

    it "does NOT persist chart data in the :enhanced marker" do
      described_class.perform_now(turn.id)
      marker = @enhanced_event.reload.payload["analyze"]
      expect(marker["views"]).to be_nil
      expect(marker["watched_hours"]).to be_nil
      expect(marker["subs"]).to be_nil
    end

    context "avg_viewed_pct chart — insight fields" do
      before { stub_scaffold }

      it "includes at_mark_pct in the avg_viewed_pct chart" do
        # series: [95, 80, 65, 50], total_pct: 72.5
        # ratio = 72.5/100 = 0.725 → at index 0.725×3 = 2.175 → lo=2, hi=3, frac=0.175
        # 65×0.825 + 50×0.175 = 53.625 + 8.75 = 62.375 → round = 62
        event, = build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
        described_class.perform_now(turn.id)
        event.reload
        chart = event.payload.dig("analyze", "avg_viewed_pct")
        expect(chart["at_mark_pct"]).to eq(62)
      end

      it "includes benchmark_word in the avg_viewed_pct chart" do
        # rel_performance: 0.52 → "typical"
        event, = build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
        described_class.perform_now(turn.id)
        event.reload
        chart = event.payload.dig("analyze", "avg_viewed_pct")
        expect(chart["benchmark_word"]).to eq("typical")
      end
    end
  end

  # ── Vid level ─────────────────────────────────────────────────────────────

  context "vid level: usable channel with a video" do
    let!(:channel) { create(:channel, :on_connection) }
    let!(:video)   { create(:video, channel: channel) }

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze vids"
      )
    end

    before do
      @system_event, @enhanced_event, @system_indicator, @enhanced_indicator =
        build_pending_events(turn, level: "vid", entity_ids: [ video.id ])
      stub_scaffold
    end

    it "writes both events to 'ready'" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(@enhanced_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "both ready bodies include the scalars grid" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).to include("pito-analytics-scalars")
      expect(@enhanced_event.reload.payload["body"]).to include("pito-analytics-scalars")
    end

    it "ready bodies have 0/1 cells" do
      described_class.perform_now(turn.id)
      [ @system_event, @enhanced_event ].each do |event|
        doc    = Nokogiri::HTML.fragment(event.reload.payload["body"])
        values = doc.css(".pito-analytics-scalars__value").map(&:text)
        expect(values).not_to be_empty
        expect(values).to all(match(/\A[01]\z/))
      end
    end

    it "resolves both thinking indicators" do
      described_class.perform_now(turn.id)
      expect(@system_indicator.reload.payload["resolved"]).to be(true)
      expect(@enhanced_indicator.reload.payload["resolved"]).to be(true)
    end

    it "stamps completed_at on the turn" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end

    it "passes the video's youtube_video_id in groups to Scaffold.for" do
      captured_subjects = []
      allow(Pito::Analytics::Scaffold).to receive(:for) do |groups:, role:, level:, **|
        captured_subjects.concat(groups.map(&:last))
        Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
      end
      described_class.perform_now(turn.id)
      video_ids = captured_subjects.select { |s| s.is_a?(Array) }.flatten
      expect(video_ids).to include(video.youtube_video_id)
    end
  end

  # ── Game level ─────────────────────────────────────────────────────────────

  context "game level: game linked to videos on a usable channel" do
    let!(:channel) { create(:channel, :on_connection) }
    let!(:video)   { create(:video, channel: channel) }
    let!(:game)    { create(:game) }
    let!(:link)    { create(:video_game_link, video: video, game: game) }

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze games"
      )
    end

    before do
      @system_event, @enhanced_event, @system_indicator, @enhanced_indicator =
        build_pending_events(turn, level: "game", entity_ids: [ game.id ])
      stub_scaffold
    end

    it "writes both events to 'ready'" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(@enhanced_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "both ready bodies include the scalars grid" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).to include("pito-analytics-scalars")
      expect(@enhanced_event.reload.payload["body"]).to include("pito-analytics-scalars")
    end

    it "resolves both thinking indicators and stamps completed_at" do
      described_class.perform_now(turn.id)
      expect(@system_indicator.reload.payload["resolved"]).to be(true)
      expect(@enhanced_indicator.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end

    it "resolves game scope via linked video ids in groups passed to Scaffold.for" do
      captured_subjects = []
      allow(Pito::Analytics::Scaffold).to receive(:for) do |groups:, role:, level:, **|
        captured_subjects.concat(groups.map(&:last))
        Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
      end
      described_class.perform_now(turn.id)
      video_ids = captured_subjects.select { |s| s.is_a?(Array) }.flatten
      expect(video_ids).to include(video.youtube_video_id)
    end
  end

  # ── Per-metric data folding (watched_hours ÷60, subs net=gained-lost) ─────

  context "per-metric chart data folding (channel level, system role)" do
    let!(:channel) { create(:channel, :on_connection) }

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze channel"
      )
    end

    before do
      @system_event, @enhanced_event, @system_indicator, @enhanced_indicator =
        build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
      stub_scaffold
    end

    it "watched_hours total is minutes/60 (raw total 6 min → 0.1 h)" do
      described_class.perform_now(turn.id)
      wh = @system_event.reload.payload.dig("analyze", "watched_hours")
      expect(wh).not_to be_nil
      # DailySeries stub returns total:6 for all calls; estimated_minutes_watched
      # total = 6 min → 6/60.0 = 0.1 hours
      expect(wh["total"]).to be_within(0.01).of(0.1)
    end

    it "subs total is net (gained minus lost; stub returns identical series so net=0)" do
      described_class.perform_now(turn.id)
      subs = @system_event.reload.payload.dig("analyze", "subs")
      expect(subs).not_to be_nil
      # Both gained and lost fold return total:6, so net per day = 0, total = 0
      expect(subs["total"]).to eq(0)
    end

    it "views total is raw (stub returns total:6 → 6)" do
      described_class.perform_now(turn.id)
      views = @system_event.reload.payload.dig("analyze", "views")
      expect(views).not_to be_nil
      expect(views["total"]).to eq(6)
    end
  end

  # ── Shared fan-out / memoisation ───────────────────────────────────────────

  context "memoisation: each role's scaffold computed exactly once per run" do
    let!(:channel) { create(:channel, :on_connection) }

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze channel"
      )
    end

    before do
      build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
    end

    it "calls Scaffold.for exactly once per role (2 total for system + enhanced)" do
      call_count = 0
      allow(Pito::Analytics::Scaffold).to receive(:for) do |role:, level:, **|
        call_count += 1
        Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
      end
      described_class.perform_now(turn.id)
      # 2 distinct roles → 2 signatures → 2 computes (memoised by the cache hash)
      expect(call_count).to eq(2)
    end
  end

  # ── Unavailable: no usable channel ────────────────────────────────────────

  context "unavailable: channel has no youtube connection" do
    let!(:channel) { create(:channel) } # no :on_connection → needs_reauth or absent

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze channel"
      )
    end

    before do
      @system_event, @enhanced_event, @system_indicator, @enhanced_indicator =
        build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
      # Scaffold.for is called with groups: [] (no usable channel) → empty map → all "0"
      stub_scaffold({})
    end

    it "writes the system event to 'ready'" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "writes the enhanced event to 'ready'" do
      described_class.perform_now(turn.id)
      expect(@enhanced_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "every cell in the system ready body is '0' (no data available)" do
      described_class.perform_now(turn.id)
      doc    = Nokogiri::HTML.fragment(@system_event.reload.payload["body"])
      values = doc.css(".pito-analytics-scalars__value").map(&:text)
      expect(values).not_to be_empty
      expect(values).to all(eq("0"))
    end

    it "every cell in the enhanced ready body is '0'" do
      described_class.perform_now(turn.id)
      doc    = Nokogiri::HTML.fragment(@enhanced_event.reload.payload["body"])
      values = doc.css(".pito-analytics-scalars__value").map(&:text)
      expect(values).not_to be_empty
      expect(values).to all(eq("0"))
    end

    it "does NOT include the unavailable note in either body (concept gone for analyze)" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).not_to include("pito-analytics-enhanced__note")
      expect(@enhanced_event.reload.payload["body"]).not_to include("pito-analytics-enhanced__note")
    end

    it "resolves both thinking indicators even when unavailable" do
      described_class.perform_now(turn.id)
      expect(@system_indicator.reload.payload["resolved"]).to be(true)
      expect(@enhanced_indicator.reload.payload["resolved"]).to be(true)
    end

    it "stamps completed_at on the turn even when unavailable" do
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Unavailable: channel needs_reauth ─────────────────────────────────────

  context "unavailable: channel connection needs_reauth" do
    let!(:connection) { create(:youtube_connection, :needs_reauth) }
    let!(:channel)    { create(:channel, youtube_connection: connection) }

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze channel"
      )
    end

    before do
      @system_event, @enhanced_event, @system_indicator, @enhanced_indicator =
        build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
      stub_scaffold({})
    end

    it "writes both events to 'ready' with all-zero cells" do
      described_class.perform_now(turn.id)
      [ @system_event, @enhanced_event ].each do |event|
        expect(event.reload.payload.dig("analyze", "status")).to eq("ready")
        doc    = Nokogiri::HTML.fragment(event.reload.payload["body"])
        values = doc.css(".pito-analytics-scalars__value").map(&:text)
        expect(values).not_to be_empty
        expect(values).to all(eq("0"))
      end
    end

    it "resolves both indicators and completes the turn" do
      described_class.perform_now(turn.id)
      expect(@system_indicator.reload.payload["resolved"]).to be(true)
      expect(@enhanced_indicator.reload.payload["resolved"]).to be(true)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end

  # ── Idempotent: second run skips already-ready events ─────────────────────

  context "idempotency: running the job twice" do
    let!(:channel) { create(:channel, :on_connection) }

    let!(:turn) do
      conversation.turns.create!(
        position:   Turn.next_position_for(conversation),
        input_kind: :chat,
        input_text: "analyze channel"
      )
    end

    before do
      build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])
    end

    it "does not call Scaffold.for a second time on the second run" do
      call_count = 0
      allow(Pito::Analytics::Scaffold).to receive(:for) do |role:, level:, **|
        call_count += 1
        Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
      end

      described_class.perform_now(turn.id)
      first_run_count = call_count

      # Second run: pending_events returns [] (all events are now 'ready')
      described_class.perform_now(turn.id)
      expect(call_count).to eq(first_run_count)
    end

    it "turn remains completed after the second run" do
      stub_scaffold
      described_class.perform_now(turn.id)
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end

    it "second run does not raise" do
      stub_scaffold
      described_class.perform_now(turn.id)
      expect { described_class.perform_now(turn.id) }.not_to raise_error
    end
  end
end
