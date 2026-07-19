# frozen_string_literal: true

require "rails_helper"

# Follow-up handler for analytics glance events (reply_target: "analytics_glance").
# Mode: :append — emits a NEW analyze pair (system + enhanced) for the scope,
# and consumes ALL followupable events in the source turn at once.
RSpec.describe Pito::FollowUp::Handlers::AnalyticsGlance, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel)     { create(:channel, :on_connection) }
  let!(:video)       { create(:video, channel:) }

  # The "show vid" turn that holds the glance and other followupable events.
  let(:show_turn) do
    conversation.turns.create!(
      input_kind: :chat, input_text: "show vid ##{video.id}", position: 1
    )
  end

  # Build a ready analytics glance event for `scope` (Video or Game).
  def build_glance_event(scope: video, payload_overrides: {})
    intro = "<span>Analytics for #{scope.respond_to?(:title) ? scope.title : scope.to_s}</span>"
    payload = {
      "body"      => "<div>glance html</div>",
      "html"      => true,
      "anchor"    => true,
      "analytics" => {
        "status"     => "ready",
        "scope_type" => scope.class.name,
        "scope_id"   => scope.id,
        "period"     => "7d",
        "intro"      => intro
      },
      "reply_handle" => "glance-0001",
      "reply_target" => "analytics_glance"
    }.deep_merge(payload_overrides)
    Event.create_with_position!(
      conversation:, turn: show_turn, kind: :enhanced, payload:
    )
  end

  # A second followupable event in the same turn (simulates detail card, etc.).
  def build_sibling_event(turn:)
    payload = {
      "body"         => "<div>detail card</div>",
      "html"         => true,
      "reply_handle" => "detail-9999",
      "reply_target" => "video_detail"
    }
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload:
    )
  end

  # Stub Scaffold.for so AnalyzePrepareJob (if triggered) never hits YouTube.
  before do
    allow(Pito::Analytics::Scaffold).to receive(:for) do |role:, level:, **|
      Pito::Analytics::MetricOrder.for(role:, level:).index_with { true }
    end
  end

  # ── class-level contract ────────────────────────────────────────────────────

  it "registers for the analytics_glance target" do
    expect(described_class.target).to eq("analytics_glance")
  end

  it "Matrix serves :append mode for analytics_glance" do
    expect(Pito::Dispatch::Matrix.mode_for("analytics_glance")).to eq(:append)
  end

  it "Matrix advertises 'with' and 'without' for analytics_glance" do
    expect(Pito::Dispatch::Matrix.actions_for("analytics_glance")).to include("with", "without")
  end

  it "Matrix advertises 'analyze' for analytics_glance" do
    expect(Pito::Dispatch::Matrix.actions_for("analytics_glance")).to include("analyze")
  end

  describe "`@ai <text>` — anchored reply (owner-scoped roster)" do
    let(:source_event) { build_glance_event }

    it "delegates to Chat::Handlers::Ai via ToolDelegator: a pending :ai event anchored on this glance (short-circuits BEFORE the analyze/with/without selection logic)" do
      result = handler.call(event: source_event, rest: "@ai is this trending up", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      pending = result.events.first
      expect(pending[:kind]).to eq(:ai)
      expect(pending[:payload]["status"]).to eq("pending")
      expect(pending[:payload]["prompt"]).to eq("is this trending up")
      expect(pending[:payload]["anchor_event_id"]).to eq(source_event.id)
    end
  end

  # ── combined (multi-id) glance: analyze re-runs over the whole set ───────────

  describe "#call — analyze on a COMBINED (scope_ids) glance" do
    let!(:video2) { create(:video, channel:) }
    let(:multi_glance) do
      build_glance_event(payload_overrides: {
        "analytics" => { "scope_id" => nil, "scope_ids" => [ video.id, video2.id ] }
      })
    end

    it "analyzes the whole set — entity_ids = both ids, title '2 vids'" do
      allow(Pito::MessageBuilder::Analyze::Message).to receive(:pair).and_return([])
      handler.call(event: multi_glance, rest: "analyze", conversation:)
      expect(Pito::MessageBuilder::Analyze::Message).to have_received(:pair).with(
        hash_including(level: :vid, entity_ids: [ video.id, video2.id ], title: "2 vids")
      )
    end
  end

  # ── with <metric> → new analyze pair ────────────────────────────────────────

  describe "#call — with <metric>" do
    let(:source_event) { build_glance_event }

    subject(:result) { handler.call(event: source_event, rest: "with views", conversation:) }

    it "returns a Result::Append" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends exactly two events (system + enhanced analyze pair)" do
      expect(result.events.length).to eq(2)
    end

    it "first event has kind :system" do
      expect(result.events.first[:kind]).to eq(:system)
    end

    it "second event has kind :enhanced" do
      expect(result.events.second[:kind]).to eq(:enhanced)
    end

    it "both events carry analyze markers in 'pending' status" do
      result.events.each do |ev|
        expect(ev[:payload].dig("analyze", "status")).to eq("pending")
      end
    end

    it "the 'with' selection is recorded in the analyze marker" do
      result.events.each do |ev|
        expect(ev[:payload].dig("analyze", "with")).to include("views")
      end
    end

    it "both events are followupable with reply_target: 'analyze_message'" do
      result.events.each do |ev|
        expect(ev[:payload]["reply_target"]).to eq("analyze_message")
        expect(ev[:payload]["reply_handle"]).to be_present
      end
    end

    it "consume: true — the source glance is consumed via the Append path" do
      expect(result.consume).to be true
    end

    it "resolves the vid-level scope (analyze level: 'vid')" do
      result.events.each do |ev|
        expect(ev[:payload].dig("analyze", "level")).to eq("vid")
      end
    end
  end

  # ── without <metric> ────────────────────────────────────────────────────────

  describe "#call — without <metric>" do
    let(:source_event) { build_glance_event }

    subject(:result) { handler.call(event: source_event, rest: "without comms", conversation:) }

    it "returns a Result::Append with two events" do
      expect(result.events.length).to eq(2)
    end

    it "the 'without' selection is recorded in the analyze marker (comms alias → canonical)" do
      result.events.each do |ev|
        expect(ev[:payload].dig("analyze", "without")).to include("comments")
      end
    end
  end

  # NOTE: retiring ALL prior-turn handles (the whole show vid/game turn) is no
  # longer the handler's job — the new pair lands as a fresh :system turn, and the
  # shared Finalizer consume mechanism sweeps every prior live handle. That is
  # covered end-to-end in spec/requests/consume_prior_replies_spec.rb.

  # ── game scope ──────────────────────────────────────────────────────────────

  describe "#call — game scope" do
    let!(:game) { create(:game, title: "Lies of P") }
    let(:source_event) { build_glance_event(scope: game) }

    subject(:result) { handler.call(event: source_event, rest: "with views", conversation:) }

    it "returns a Result::Append with two events" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events.length).to eq(2)
    end

    it "resolves the game-level scope (analyze level: 'game')" do
      result.events.each do |ev|
        expect(ev[:payload].dig("analyze", "level")).to eq("game")
      end
    end
  end

  # ── scope not found ─────────────────────────────────────────────────────────

  describe "#call — scope not found (bad scope_id)" do
    let(:source_event) do
      build_glance_event(payload_overrides: {
        "analytics" => {
          "status"     => "ready",
          "scope_type" => "Video",
          "scope_id"   => 999_999,
          "period"     => "7d",
          "intro"      => ""
        }
      })
    end

    it "returns a Result::Error" do
      result = handler.call(event: source_event, rest: "with views", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the analytics_glance.errors.scope_not_found message key" do
      result = handler.call(event: source_event, rest: "with views", conversation:)
      expect(result.message_key).to eq("pito.follow_up.analytics_glance.errors.scope_not_found")
    end
  end

  # ── invalid action ──────────────────────────────────────────────────────────

  describe "#call — invalid action" do
    let(:source_event) { build_glance_event }

    it "returns a Result::Error for an unrecognised action" do
      result = handler.call(event: source_event, rest: "show views", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.analytics_glance.errors.invalid_action")
    end
  end

  # ── analyze (no filter) on video scope ─────────────────────────────────────

  describe "#call — analyze on video scope" do
    let(:source_event) { build_glance_event }

    subject(:result) { handler.call(event: source_event, rest: "analyze", conversation:) }

    it "returns a Result::Append (not invalid_action)" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a non-empty events list" do
      expect(result.events).not_to be_empty
    end

    it "passes selection: nil so no metric filtering is applied" do
      result.events.each do |ev|
        expect(ev[:payload].dig("analyze", "with")).to be_blank
        expect(ev[:payload].dig("analyze", "without")).to be_blank
      end
    end
  end

  # ── analyze on game scope ───────────────────────────────────────────────────

  describe "#call — analyze on game scope" do
    let!(:game)        { create(:game, title: "Lies of P") }
    let(:source_event) { build_glance_event(scope: game) }

    subject(:result) { handler.call(event: source_event, rest: "analyze", conversation:) }

    it "returns a Result::Append (works for game level too)" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.events).not_to be_empty
    end
  end

  # ── channel scope ───────────────────────────────────────────────────────────

  describe "#call — channel scope" do
    let!(:glance_channel) { create(:channel, handle: "testchan") }
    let(:source_event)    { build_glance_event(scope: glance_channel) }

    subject(:result) { handler.call(event: source_event, rest: "analyze", conversation:) }

    it "returns a Result::Append (not scope_not_found)" do
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "appends a non-empty events list" do
      expect(result.events).not_to be_empty
    end

    it "resolves the channel-level scope (analyze level: 'channel')" do
      result.events.each do |ev|
        expect(ev[:payload].dig("analyze", "level")).to eq("channel")
      end
    end
  end

  # ── regression: existing actions still work, unknown action still errors ────

  describe "#call — regression guards" do
    let(:source_event) { build_glance_event }

    it "'with <metric>' still returns a Result::Append" do
      result = handler.call(event: source_event, rest: "with views", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "an unknown action (e.g. 'bogus') still returns invalid_action Error" do
      result = handler.call(event: source_event, rest: "bogus views", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.analytics_glance.errors.invalid_action")
    end
  end

  # ── registry ────────────────────────────────────────────────────────────────

  describe "registry" do
    before { Pito::FollowUp::Registry.register(described_class) }

    it "is registered under 'analytics_glance'" do
      expect(Pito::FollowUp::Registry.for("analytics_glance")).to eq(described_class)
    end

    it "has mode :append" do
      expect(Pito::FollowUp::Registry.mode_for("analytics_glance")).to eq(:append)
    end
  end
end
