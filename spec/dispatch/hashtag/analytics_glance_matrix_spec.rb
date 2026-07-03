# frozen_string_literal: true

require "rails_helper"

# ── Recognition matrix: analytics_glance hashtag follow-up (DB fully mocked) ──
#
# RULE: every declared action is recognized — no exception.
# DB fully mocked (zero factories). Source events are plain doubles carrying the
# analytics payload structure the handler reads. MessageBuilder::Analyze::Message.pair
# is stubbed to a sentinel so this spec tests ROUTING, not builder output.
#
# Declared actions (3): with · without · analyze
# + unknown → invalid_action Error
#
# Scope resolution: Video (level :vid), Game (level :game), Channel (level :channel).
# scope_not_found: find_by returns nil.
#
# Bug contract: a declared action that hits invalid_action is a BUG — this spec
# will fail on that action and the failure is reported verbatim.
RSpec.describe "Dispatch matrix — analytics_glance follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler)      { Pito::FollowUp::Handlers::AnalyticsGlance.new }
  let(:conversation) { instance_double(Conversation, stats_period: "7d") }

  # DB stubs — no factories.
  # respond_to?(:at_handle): true for channel (at_handle stubbed), false for video/game.
  let(:video_stub)   { double("Video",   id: 42, title: "Test Video") }
  let(:game_stub)    { double("Game",    id: 99, title: "Hollow Knight") }
  let(:channel_stub) { double("Channel", id: 5,  at_handle: "@testchan") }

  # Sentinel pair returned by the builder stub (2 events, matches Append shape).
  let(:sentinel_pair) do
    [
      { kind: :system,   payload: { "analyze" => { "status" => "pending", "role" => "system",   "level" => "vid", "with" => [], "without" => [] } } },
      { kind: :enhanced, payload: { "analyze" => { "status" => "pending", "role" => "enhanced", "level" => "vid", "with" => [], "without" => [] } } }
    ]
  end

  # Build a minimal glance event double for the given scope_type/scope_id (no DB).
  def glance_event(scope_type:, scope_id:)
    double("Event", payload: {
      "analytics" => {
        "status"     => "ready",
        "scope_type" => scope_type,
        "scope_id"   => scope_id,
        "period"     => "7d",
        "intro"      => "<span>Analytics</span>"
      }
    })
  end

  let(:video_event)   { glance_event(scope_type: "Video",   scope_id: 42) }
  let(:game_event)    { glance_event(scope_type: "Game",    scope_id: 99) }
  let(:channel_event) { glance_event(scope_type: "Channel", scope_id: 5) }

  before do
    allow(::Video).to   receive(:find_by).with(id: 42).and_return(video_stub)
    allow(::Game).to    receive(:find_by).with(id: 99).and_return(game_stub)
    allow(::Channel).to receive(:find_by).with(id: 5).and_return(channel_stub)

    allow(Pito::MessageBuilder::Analyze::Message).to receive(:pair).and_return(sentinel_pair)
  end

  def call(event:, rest:)
    handler.call(event: event, rest: rest, conversation: conversation)
  end

  # ── Registry ────────────────────────────────────────────────────────────────

  describe "Registry" do
    it "resolves 'analytics_glance' to Handlers::AnalyticsGlance" do
      expect(Pito::FollowUp::Registry.for("analytics_glance"))
        .to eq(Pito::FollowUp::Handlers::AnalyticsGlance)
    end

    it "mode_for('analytics_glance') is :append" do
      expect(Pito::FollowUp::Registry.mode_for("analytics_glance")).to eq(:append)
    end

    it "actions_for('analytics_glance') is exactly ['with', 'without', 'analyze']" do
      expect(Pito::FollowUp::Registry.actions_for("analytics_glance"))
        .to match_array(%w[with without analyze])
    end

    it "class target is 'analytics_glance'" do
      expect(Pito::FollowUp::Handlers::AnalyticsGlance.target).to eq("analytics_glance")
    end

    it "Matrix serves :append mode for analytics_glance" do
      expect(Pito::Dispatch::Matrix.mode_for("analytics_glance")).to eq(:append)
    end
  end

  # ── 'with' action ───────────────────────────────────────────────────────────

  describe "'with' action → Result::Append (not invalid_action)" do
    {
      "single metric"         => "with views",
      "comma-separated list"  => "with views,comments",
      "space-separated list"  => "with views comments",
      "aliased metric (comms → comments)" => "with comms"
    }.each do |desc, rest_input|
      context desc do
        subject(:result) { call(event: video_event, rest: rest_input) }

        it "returns Result::Append" do
          expect(result).to be_a(Pito::FollowUp::Result::Append)
        end

        it "is NOT a Result::Error (not invalid_action)" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to Message.pair (not short-circuited)" do
          result
          expect(Pito::MessageBuilder::Analyze::Message).to have_received(:pair)
        end
      end
    end
  end

  # ── 'without' action ─────────────────────────────────────────────────────────

  describe "'without' action → Result::Append (not invalid_action)" do
    {
      "single metric"        => "without views",
      "comma-separated list" => "without views,comments",
      "space-separated list" => "without views comments"
    }.each do |desc, rest_input|
      context desc do
        subject(:result) { call(event: video_event, rest: rest_input) }

        it "returns Result::Append" do
          expect(result).to be_a(Pito::FollowUp::Result::Append)
        end

        it "is NOT a Result::Error (not invalid_action)" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to Message.pair" do
          result
          expect(Pito::MessageBuilder::Analyze::Message).to have_received(:pair)
        end
      end
    end
  end

  # ── 'analyze' action (bare full re-analyze) ───────────────────────────────────

  describe "'analyze' action (bare) → Result::Append, selection: nil" do
    subject(:result) { call(event: video_event, rest: "analyze") }

    it "returns Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "is NOT a Result::Error (not invalid_action)" do
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "calls pair with selection: nil (no metric filtering)" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(selection: nil))
    end

    it "calls pair with the video scope (level: :vid)" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(level: :vid))
    end
  end

  # ── Scope resolution ─────────────────────────────────────────────────────────

  describe "scope resolution — Video → level :vid" do
    subject(:result) { call(event: video_event, rest: "with views") }

    it "calls ::Video.find_by with the scope_id" do
      result
      expect(::Video).to have_received(:find_by).with(id: 42)
    end

    it "returns Result::Append (not scope_not_found)" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "calls pair with level: :vid" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(level: :vid))
    end

    it "calls pair with entity_ids: [42]" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(entity_ids: [ 42 ]))
    end
  end

  describe "scope resolution — Game → level :game" do
    subject(:result) { call(event: game_event, rest: "with views") }

    it "calls ::Game.find_by with the scope_id" do
      result
      expect(::Game).to have_received(:find_by).with(id: 99)
    end

    it "returns Result::Append (not scope_not_found)" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "calls pair with level: :game" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(level: :game))
    end

    it "calls pair with entity_ids: [99]" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(entity_ids: [ 99 ]))
    end
  end

  describe "scope resolution — Channel → level :channel" do
    subject(:result) { call(event: channel_event, rest: "analyze") }

    it "calls ::Channel.find_by with the scope_id" do
      result
      expect(::Channel).to have_received(:find_by).with(id: 5)
    end

    it "returns Result::Append (not scope_not_found)" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "calls pair with level: :channel" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(level: :channel))
    end

    it "calls pair with entity_ids: [5]" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(entity_ids: [ 5 ]))
    end

    it "uses at_handle as title (channel responds to at_handle)" do
      result
      expect(Pito::MessageBuilder::Analyze::Message)
        .to have_received(:pair).with(hash_including(title: "@testchan"))
    end
  end

  describe "scope_not_found — find_by returns nil" do
    let(:missing_event) { glance_event(scope_type: "Video", scope_id: 9999) }

    before { allow(::Video).to receive(:find_by).with(id: 9999).and_return(nil) }

    subject(:result) { call(event: missing_event, rest: "with views") }

    it "returns Result::Error" do
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the scope_not_found message key" do
      expect(result.message_key)
        .to eq("pito.follow_up.analytics_glance.errors.scope_not_found")
    end

    it "does NOT call Message.pair" do
      result
      expect(Pito::MessageBuilder::Analyze::Message).not_to have_received(:pair)
    end
  end

  # ── Unknown action → invalid_action Error ───────────────────────────────────

  describe "unknown action → invalid_action Error" do
    %w[show bogus edit help frobnicate update].each do |unknown|
      context "#{unknown.inspect} (not declared)" do
        subject(:result) { call(event: video_event, rest: unknown) }

        it "returns Result::Error" do
          expect(result).to be_a(Pito::FollowUp::Result::Error)
        end

        it "uses the invalid_action message key" do
          expect(result.message_key)
            .to eq("pito.follow_up.analytics_glance.errors.invalid_action")
        end

        it "includes the unknown action in message_args" do
          expect(result.message_args).to include(action: unknown)
        end

        it "does NOT return Result::Append" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Append)
        end

        it "does NOT call Message.pair" do
          result
          expect(Pito::MessageBuilder::Analyze::Message).not_to have_received(:pair)
        end
      end
    end
  end
end
