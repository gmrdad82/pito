# frozen_string_literal: true

require "rails_helper"

# Follow-up handler for `analyze` messages (reply_target: "analyze_message").
# Mode: :mutate — re-renders the 0/1 cells in-place from the persisted scaffold.
# Actions: "with" / "without" — accumulates the metric selection.
RSpec.describe Pito::FollowUp::Handlers::AnalyzeMessage, type: :service do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }

  let(:turn) do
    conversation.turns.create!(
      input_kind: :hashtag, input_text: "#analyze-test without comms", position: 1
    )
  end

  # Build a full scaffold (all metrics pulled) for system/channel.
  let(:full_scaffold) do
    Pito::Analytics::MetricOrder.for(role: :system, level: :channel).index_with { true }
  end

  # Build a ready analyze event with scaffold persisted in the marker and
  # followupable fields set.  payload_overrides can patch the marker for
  # specific edge-case tests.
  def build_analyze_event(payload_overrides = {}, role: "system", level: :channel)
    pending_p = Pito::MessageBuilder::Analyze::Message.pending(
      role:, title: "My Channel", level:, entity_ids: [ 1 ], period: "7d", conversation:
    )
    scaffold = Pito::Analytics::MetricOrder.for(role: role.to_sym, level:).index_with { true }
    pending_event_stub = instance_double("Event", payload: pending_p)
    ready_p = Pito::MessageBuilder::Analyze::Message.ready_payload(
      pending_event_stub, data: { scaffold:, views: nil }
    )
    Event.create_with_position!(
      conversation:, turn:, kind: :system, payload: ready_p.merge(payload_overrides)
    )
  end

  # ── class-level contract ────────────────────────────────────────────────────

  it "registers for the analyze_message target in :mutate mode" do
    expect(described_class.target).to eq("analyze_message")
    expect(described_class.mode).to eq(:mutate)
  end

  it "declares 'with' and 'without' as actions" do
    expect(described_class.actions).to include("with", "without")
  end

  # ── without <metric> ────────────────────────────────────────────────────────

  describe "#call — without <metric>" do
    let(:source_event) { build_analyze_event }

    subject(:result) { handler.call(event: source_event, rest: "without comms", conversation:) }

    it "returns a Result::Mutation" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "kind matches the source event kind" do
      expect(result.kind).to eq(:system)
    end

    it "accumulates the comments metric in the without list (comms alias → canonical)" do
      expect(result.payload.dig("analyze", "without")).to include("comments")
    end

    it "body no longer renders the comments cell" do
      # comments label in locale is "Comments" (pito.copy.analytics.metrics.comments)
      doc    = Nokogiri::HTML.fragment(result.payload["body"])
      labels = doc.css(".pito-analytics-scalars__label").map(&:text)
      expect(labels).not_to include("Comments")
    end

    it "still renders other metric cells (e.g. Views)" do
      # Views is an Area metric; with no chart data it renders the NoData placeholder,
      # whose caption carries the "Views" label — so the cell is still present.
      expect(result.payload["body"]).to include("Views")
    end

    it "preserves the reply_handle from the source event" do
      expect(result.payload["reply_handle"]).to eq(source_event.payload["reply_handle"])
    end

    it "preserves reply_target: 'analyze_message'" do
      expect(result.payload["reply_target"]).to eq("analyze_message")
    end

    it "sets analyze.status to 'ready' in the mutated payload" do
      expect(result.payload.dig("analyze", "status")).to eq("ready")
    end
  end

  # ── with <metric> re-includes ───────────────────────────────────────────────

  describe "#call — with <metric> un-excludes a previously excluded metric" do
    let(:source_event) do
      # Comments now lives in the :enhanced card as an area chart — simulate a prior
      # "without comms" there (marker has without: ["comms"]).
      build_analyze_event(role: "enhanced").tap do |event|
        marker = event.payload.fetch("analyze")
        event.update!(payload: event.payload.merge(
          "analyze" => marker.merge("without" => [ "comms" ])
        ))
      end
    end

    subject(:result) { handler.call(event: source_event, rest: "with comms", conversation:) }

    it "returns a Result::Mutation" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "removes the comments metric from the without list" do
      expect(result.payload.dig("analyze", "without")).not_to include("comments")
    end

    it "body includes the comments cell again" do
      # With no persisted comments chart data, the re-included comments metric renders
      # as its NoData placeholder whose caption is the metric label ("Comments").
      expect(result.payload["body"]).to include("Comments")
    end
  end

  # ── invalid action ──────────────────────────────────────────────────────────

  describe "#call — invalid action" do
    let(:source_event) { build_analyze_event }

    it "returns a Result::Error for an unrecognised action" do
      result = handler.call(event: source_event, rest: "show comms", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the analyze_message.errors.invalid_action message key" do
      result = handler.call(event: source_event, rest: "frobnicate", conversation:)
      expect(result.message_key).to eq("pito.follow_up.analyze_message.errors.invalid_action")
    end
  end

  # ── empty metrics list ──────────────────────────────────────────────────────

  describe "#call — no metrics named" do
    let(:source_event) { build_analyze_event }

    it "returns a Result::Error when 'without' has no metrics" do
      result = handler.call(event: source_event, rest: "without", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.analyze_message.errors.no_metrics")
    end

    it "returns a Result::Error when 'with' has no metrics" do
      result = handler.call(event: source_event, rest: "with", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.analyze_message.errors.no_metrics")
    end
  end

  # ── multiple metrics ────────────────────────────────────────────────────────

  describe "#call — multiple metrics comma-separated" do
    let(:source_event) { build_analyze_event }

    it "excludes all listed metrics (comms alias → canonical comments)" do
      result = handler.call(event: source_event, rest: "without comms,likes", conversation:)
      without = result.payload.dig("analyze", "without")
      expect(without).to include("comments", "likes")
    end
  end

  # ── registry ────────────────────────────────────────────────────────────────

  describe "registry" do
    before { Pito::FollowUp::Registry.register(described_class) }

    it "is registered under 'analyze_message'" do
      expect(Pito::FollowUp::Registry.for("analyze_message")).to eq(described_class)
    end

    it "has mode :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("analyze_message")).to eq(:mutate)
    end
  end
end
