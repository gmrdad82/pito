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

  it "registers for the analytics_glance target in :append mode" do
    expect(described_class.target).to eq("analytics_glance")
    expect(described_class.mode).to eq(:append)
  end

  it "declares 'with' and 'without' as actions" do
    expect(described_class.actions).to include("with", "without")
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
