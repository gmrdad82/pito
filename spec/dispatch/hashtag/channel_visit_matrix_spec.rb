# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: channel_visit hashtag follow-up (recognition, DB mocked) ──
#
# RULE: every declared action is gated in — no exception.
# All DB mocked (zero factories). Source event carries channel_id: 9 and
# visit_destination in payload.
#
# Target:          "channel_visit"
# Mode:            :mutate  (transforms event in place; no echo, no turn)
# Declared action: "consume"
# Internal:        true  ← never user-typeable; not in help or suggestions;
#                         no reply_handle stamped on the event
#
# channel_visit is the RESULT card produced by ChannelDetail's "visit" action.
# The pito--auto-visit Stimulus controller auto-clicks the hidden link once, then
# POSTs to Channels::VisitsController#consume, which routes "consume" here via
# the standard FollowUpDispatchJob mutation path.
#
# Routing in ChannelVisit#call:
#   "consume" + channel found    → Result::Mutation(kind: "system_follow_up")
#   "consume" + channel absent   → channel_not_found Error
#   unknown action               → invalid_action Error (returned directly)
#
# visit_destination preservation:
#   "channel"  → :channel  destination passed to builder
#   "studio"   → :studio   destination passed to builder
#   nil/other  → :channel  (safe default)
#
# DB stubs:  ::Channel.find_by(id: 9) → channel_stub.
# Builder stub: Pito::MessageBuilder::Channel::Visit.call → visited_payload.
#
# Bug contract: a declared action that returns invalid_action Error is a BUG.
RSpec.describe "Dispatch matrix — #channel_visit follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler) { Pito::FollowUp::Handlers::ChannelVisit.new }

  let(:channel_stub) do
    double("Channel", id: 9, handle: "@alpha", youtube_channel_id: "UCabc")
  end

  # Canned payload returned by the stubbed Visit builder (visited state).
  let(:visited_payload) do
    { "body" => "<visited/>", "channel_id" => 9, "visit_state" => "visited", "visit_destination" => "channel" }
  end

  let(:conversation) { instance_double(Conversation) }

  before do
    allow(::Channel).to receive(:find_by).with(id: 9).and_return(channel_stub)
    allow(Pito::MessageBuilder::Channel::Visit).to receive(:call).and_return(visited_payload)
  end

  # Build a source event with the given payload overrides.
  # Base payload: channel_id 9 + visit_destination "channel".
  def build_event(overrides = {})
    instance_double(
      Event,
      payload: { "channel_id" => 9, "visit_destination" => "channel" }.merge(overrides)
    )
  end

  def call(rest, source_event = build_event)
    handler.call(event: source_event, rest:, conversation:)
  end

  # ── Registry — internal handler ────────────────────────────────────────────────

  describe "Registry — internal handler" do
    it "resolves 'channel_visit' to Handlers::ChannelVisit" do
      expect(Pito::FollowUp::Registry.for("channel_visit"))
        .to eq(Pito::FollowUp::Handlers::ChannelVisit)
    end

    it "target is 'channel_visit'" do
      expect(Pito::FollowUp::Handlers::ChannelVisit.target).to eq("channel_visit")
    end

    it "mode is :mutate (transforms event in place; no echo, no new turn)" do
      expect(Pito::FollowUp::Handlers::ChannelVisit.mode).to eq(:mutate)
    end

    it "mode_for('channel_visit') is :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("channel_visit")).to eq(:mutate)
    end

    it "is internal (never user-typeable; excluded from help and suggestions)" do
      expect(Pito::FollowUp::Handlers::ChannelVisit.internal?).to be true
    end

    it "declares only 'consume' as an action" do
      expect(Pito::FollowUp::Handlers::ChannelVisit.actions).to eq([ "consume" ])
    end

    it "actions_for('channel_visit') contains 'consume'" do
      expect(Pito::FollowUp::Registry.actions_for("channel_visit")).to include("consume")
    end
  end

  # ── consume — declared action → Result::Mutation ──────────────────────────────

  describe "'consume' — declared action → Result::Mutation" do
    subject(:result) { call("consume") }

    it "returns a Result::Mutation" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "mutation kind is 'system_follow_up'" do
      expect(result.kind).to eq("system_follow_up")
    end

    it "does NOT return a Result::Error" do
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "resolves channel via ::Channel.find_by(id: 9)" do
      result
      expect(::Channel).to have_received(:find_by).with(id: 9)
    end

    it "calls Visit builder with channel_stub and state: :visited" do
      result
      expect(Pito::MessageBuilder::Channel::Visit).to have_received(:call)
        .with(channel_stub, state: :visited, destination: anything)
    end

    it "mutation payload is the stubbed visited_payload" do
      expect(result.payload).to eq(visited_payload)
    end
  end

  # ── consume preserves visit_destination from the source event payload ─────────

  describe "'consume' — visit_destination preservation" do
    context "visit_destination: 'channel' → destination :channel" do
      it "calls Visit builder with destination: :channel" do
        call("consume", build_event("visit_destination" => "channel"))
        expect(Pito::MessageBuilder::Channel::Visit).to have_received(:call)
          .with(channel_stub, state: :visited, destination: :channel)
      end
    end

    context "visit_destination: 'studio' → destination :studio" do
      it "calls Visit builder with destination: :studio" do
        call("consume", build_event("visit_destination" => "studio"))
        expect(Pito::MessageBuilder::Channel::Visit).to have_received(:call)
          .with(channel_stub, state: :visited, destination: :studio)
      end
    end

    context "visit_destination: nil → defaults to :channel" do
      it "calls Visit builder with destination: :channel (safe default)" do
        call("consume", build_event("visit_destination" => nil))
        expect(Pito::MessageBuilder::Channel::Visit).to have_received(:call)
          .with(channel_stub, state: :visited, destination: :channel)
      end
    end

    context "visit_destination: unrecognised value → defaults to :channel" do
      it "calls Visit builder with destination: :channel" do
        call("consume", build_event("visit_destination" => "bogus"))
        expect(Pito::MessageBuilder::Channel::Visit).to have_received(:call)
          .with(channel_stub, state: :visited, destination: :channel)
      end
    end
  end

  # ── consume — channel not found ────────────────────────────────────────────────

  describe "'consume' — channel not found → channel_not_found Error" do
    before { allow(::Channel).to receive(:find_by).with(id: 9).and_return(nil) }

    it "returns a Result::Error" do
      result = call("consume")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the channel_not_found message key" do
      result = call("consume")
      expect(result.message_key).to eq("pito.follow_up.channel_visit.errors.channel_not_found")
    end

    it "does NOT call Visit builder when channel is missing" do
      call("consume")
      expect(Pito::MessageBuilder::Channel::Visit).not_to have_received(:call)
    end
  end

  # ── Unknown action → invalid_action Error ─────────────────────────────────────
  #
  # channel_visit declares only "consume". Any other action returns invalid_action
  # directly (no VerbDelegator involvement — handler does not delegate).

  describe "unknown action → invalid_action Error" do
    %w[visit sync open show delete rm shinies bogus nope].each do |unknown|
      context unknown.inspect do
        subject(:result) { call(unknown) }

        it "returns a Result::Error" do
          expect(result).to be_a(Pito::FollowUp::Result::Error)
        end

        it "uses the channel_visit invalid_action message key" do
          expect(result.message_key).to eq("pito.follow_up.channel_visit.errors.invalid_action")
        end

        it "includes the offending action in message_args" do
          expect(result.message_args).to include(action: unknown)
        end

        it "does NOT call Visit builder" do
          result
          expect(Pito::MessageBuilder::Channel::Visit).not_to have_received(:call)
        end
      end
    end
  end
end
