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
