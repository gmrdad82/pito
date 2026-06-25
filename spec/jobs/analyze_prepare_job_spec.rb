# frozen_string_literal: true

require "rails_helper"

# Fills the two pending analyze events (system + enhanced) for a turn, resolves
# each message's per-message thinking indicator, and completes the turn.
#
# Scope dispatch:
#   channel level → Primitives.fetch with :channel subject (videos: nil)
#   vid level     → Primitives.fetch with [youtube_video_id] subjects
#   game level    → resolves via linked videos, same Primitives path
#
# Fan-out memoisation: both messages share one scope signature → compute runs
# once → client called at most N times (N = 1 + 1 for previous window), not 2N.
RSpec.describe AnalyzePrepareJob, type: :job do
  let(:conversation) { Conversation.singleton }

  # Raw scalar metrics returned by the stubbed AnalyticsClient (symbol keys —
  # the real API returns them; `normalize` in Primitives stringifies them).
  let(:raw_metrics) do
    {
      views:                     1234,
      estimated_minutes_watched: 720,
      average_view_duration:     245,
      average_view_percentage:   38.2,
      subscribers_gained:        20,
      subscribers_lost:          9,
      likes:                     210,
      dislikes:                  4,
      comments:                  31
    }
  end

  def stub_client(return_value = raw_metrics)
    allow_any_instance_of(::Channel::Youtube::AnalyticsClient)
      .to receive(:scalars)
      .and_return(return_value)
  end

  # Persist a pair of pending analyze events (system + enhanced) for `turn` at
  # `level` with the given `entity_ids`, each linked to its own thinking
  # indicator. Returns [system_event, enhanced_event, system_indicator,
  # enhanced_indicator] so callers can call .reload on each.
  def build_pending_events(turn, level:, entity_ids:, period: "7d")
    events = Pito::MessageBuilder::Analyze::Message::ROLES.map do |role|
      kind = role == "system" ? :system : :enhanced
      payload = Pito::MessageBuilder::Analyze::Message.pending(
        role: role, title: "Test Scope", level: level,
        entity_ids: entity_ids, period: period
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

    let!(:system_event)        { nil } # populated below
    let!(:enhanced_event)      { nil }
    let!(:system_indicator)    { nil }
    let!(:enhanced_indicator)  { nil }

    before do
      sys_ev, enh_ev, sys_ind, enh_ind =
        build_pending_events(turn, level: "channel", entity_ids: [ channel.id ])

      # Reassign instance vars so examples can call .reload on each.
      @system_event       = sys_ev
      @enhanced_event     = enh_ev
      @system_indicator   = sys_ind
      @enhanced_indicator = enh_ind

      stub_client
    end

    it "writes the system event to status 'ready'" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "writes the enhanced event to status 'ready'" do
      described_class.perform_now(turn.id)
      expect(@enhanced_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "body of the ready system event includes the scalars table" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).to include("pito-analytics-scalars")
    end

    it "body of the ready enhanced event includes the scalars table" do
      described_class.perform_now(turn.id)
      expect(@enhanced_event.reload.payload["body"]).to include("pito-analytics-scalars")
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

    it "calls the client with videos: nil (channel-wide, not per-video)" do
      videos_args = []
      allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:scalars) do |_, **kwargs|
        videos_args << kwargs[:videos]
        raw_metrics
      end
      described_class.perform_now(turn.id)
      expect(videos_args).not_to be_empty
      expect(videos_args).to all(be_nil)
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
      stub_client
    end

    it "writes both events to 'ready'" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(@enhanced_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "both ready bodies include the scalars table" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).to include("pito-analytics-scalars")
      expect(@enhanced_event.reload.payload["body"]).to include("pito-analytics-scalars")
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

    it "calls the client with the video's youtube_video_id" do
      videos_args = []
      allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:scalars) do |_, **kwargs|
        videos_args << kwargs[:videos]
        raw_metrics
      end
      described_class.perform_now(turn.id)
      expect(videos_args.flatten.compact).to include(video.youtube_video_id)
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
      stub_client
    end

    it "writes both events to 'ready'" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(@enhanced_event.reload.payload.dig("analyze", "status")).to eq("ready")
    end

    it "both ready bodies include the scalars table" do
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
  end

  # ── Shared fan-out / memoisation ───────────────────────────────────────────

  context "shared fan-out: two messages share the same scope signature" do
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

    it "calls the client fewer times than (messages × windows) — memoisation works" do
      call_count = 0
      allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:scalars) do
        call_count += 1
        raw_metrics
      end

      described_class.perform_now(turn.id)

      # Without memoisation: 2 messages × (current + previous window) = up to 4 calls.
      # With memoisation:    1 compute  × (current + previous window) = up to 2 calls.
      expect(call_count).to be <= 2
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
      # No client stub needed — groups_for returns [] so Primitives is never called.
    end

    it "writes the system event to 'ready' with the unavailable note" do
      described_class.perform_now(turn.id)
      payload = @system_event.reload.payload
      expect(payload.dig("analyze", "status")).to eq("ready")
      expect(payload["body"]).to include("pito-analytics-enhanced__note")
    end

    it "writes the enhanced event to 'ready' with the unavailable note" do
      described_class.perform_now(turn.id)
      payload = @enhanced_event.reload.payload
      expect(payload.dig("analyze", "status")).to eq("ready")
      expect(payload["body"]).to include("pito-analytics-enhanced__note")
    end

    it "does NOT include the scalars table in either ready body" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload["body"]).not_to include("pito-analytics-scalars")
      expect(@enhanced_event.reload.payload["body"]).not_to include("pito-analytics-scalars")
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
    end

    it "writes both events to 'ready' with the unavailable note" do
      described_class.perform_now(turn.id)
      expect(@system_event.reload.payload.dig("analyze", "status")).to eq("ready")
      expect(@enhanced_event.reload.payload["body"]).to include("pito-analytics-enhanced__note")
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

    it "does not call the client a second time on the second run" do
      call_count = 0
      allow_any_instance_of(::Channel::Youtube::AnalyticsClient).to receive(:scalars) do
        call_count += 1
        raw_metrics
      end

      described_class.perform_now(turn.id)
      first_run_count = call_count

      # Second run: pending_events returns [] because both events are now 'ready'.
      described_class.perform_now(turn.id)
      expect(call_count).to eq(first_run_count)
    end

    it "turn remains completed after the second run" do
      stub_client
      described_class.perform_now(turn.id)
      described_class.perform_now(turn.id)
      expect(turn.reload.completed_at).not_to be_nil
    end
  end
end
