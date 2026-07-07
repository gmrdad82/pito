# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: channel_list hashtag follow-up (recognition, DB mocked) ──
#
# RULE: every declared action is gated in — no exception.
# All DB mocked (zero factories). Source event via instance_double(Event).
#
# Target: "channel_list", mode: :append
# Declared actions: "shinies"
#
# Routing in ChannelList#call:
#   "shinies"      → VerbDelegator (delegates to Chat::Handlers::Shinies)
#   unknown action → Result::Error (invalid_action) — returned directly, no VerbDelegator
#
# Bug contract: a declared action that returns invalid_action Error is a BUG.
RSpec.describe "Dispatch matrix — #channel_list follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler) { Pito::FollowUp::Handlers::ChannelList.new }

  let(:source_event) do
    instance_double(Event, payload: { "reply_target" => "channel_list" })
  end

  let(:conversation) { instance_double(Conversation) }

  # Sentinel returned by VerbDelegator for every delegated action.
  let(:sentinel) { Pito::FollowUp::Result::Append.new(events: [], consume: false) }

  before do
    allow(Pito::FollowUp::VerbDelegator).to receive(:call).and_return(sentinel)
  end

  def call(rest)
    handler.call(event: source_event, rest:, conversation:)
  end

  # ── Registry ──────────────────────────────────────────────────────────────────

  describe "Registry" do
    it "resolves 'channel_list' to Handlers::ChannelList" do
      expect(Pito::FollowUp::Registry.for("channel_list"))
        .to eq(Pito::FollowUp::Handlers::ChannelList)
    end

    it "mode_for('channel_list') is :append" do
      expect(Pito::FollowUp::Registry.mode_for("channel_list")).to eq(:append)
    end

    it "target is 'channel_list'" do
      expect(Pito::FollowUp::Handlers::ChannelList.target).to eq("channel_list")
    end

    it "Matrix serves :append mode for channel_list" do
      expect(Pito::Dispatch::Matrix.mode_for("channel_list")).to eq(:append)
    end

    it "Matrix advertises shinies, analyze, the sort/order pair, and next for channel_list" do
      expect(Pito::Dispatch::Matrix.actions_for("channel_list"))
        .to include("shinies", "analyze", "sort", "order", "next")
    end

    it "actions_for('channel_list') matches the declared set (with/without joined — G26.2; segment verbs G123; vids/more aliases)" do
      expect(Pito::FollowUp::Registry.actions_for("channel_list"))
        .to match_array(%w[shinies analyze sort order next more with without at-a-glance videos vids games])
    end

    it "sort and order are :mutate actions (re-render in place, no consume)" do
      expect(Pito::FollowUp::Registry.mode_for("channel_list", action: "sort")).to eq(:mutate)
      expect(Pito::FollowUp::Registry.mode_for("channel_list", action: "order")).to eq(:mutate)
    end

    it "with and without are :mutate actions (column set re-renders in place — G26.2)" do
      expect(Pito::FollowUp::Registry.mode_for("channel_list", action: "with")).to eq(:mutate)
      expect(Pito::FollowUp::Registry.mode_for("channel_list", action: "without")).to eq(:mutate)
    end

    it "does NOT include 'visit' (visit moved to channel_detail)" do
      expect(Pito::FollowUp::Registry.actions_for("channel_list")).not_to include("visit")
    end

    it "is not internal (appears in suggestions)" do
      expect(Pito::FollowUp::Handlers::ChannelList.internal?).to be false
    end
  end

  # ── shinies — declared action, delegates to VerbDelegator ─────────────────────

  describe "'shinies' — declared action → delegates to VerbDelegator" do
    context "shinies @handle" do
      subject(:result) { call("shinies @mychannel") }

      it "does NOT return a Result::Error (not invalid_action)" do
        expect(result).not_to be_a(Pito::FollowUp::Result::Error)
      end

      it "delegates to VerbDelegator.call with source_event, full rest, conversation" do
        result
        expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
          hash_including(source_event:, rest: "shinies @mychannel", conversation:)
        )
      end

      it "returns the sentinel Append from VerbDelegator" do
        expect(result).to eq(sentinel)
      end
    end

    context "bare 'shinies' (no handle argument)" do
      subject(:result) { call("shinies") }

      it "still delegates to VerbDelegator (not invalid_action)" do
        expect(result).not_to be_a(Pito::FollowUp::Result::Error)
      end

      it "delegates with rest: 'shinies'" do
        result
        expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
          hash_including(source_event:, rest: "shinies", conversation:)
        )
      end

      it "returns the sentinel Append" do
        expect(result).to eq(sentinel)
      end
    end
  end

  # ── Unknown action → invalid_action Error ─────────────────────────────────────
  #
  # channel_list declares only "shinies". All other verbs return invalid_action
  # directly (no VerbDelegator involvement).

  describe "unknown action → invalid_action Error" do
    %w[visit open sync show help delete rm reindex bogus].each do |unknown|
      context unknown.inspect do
        subject(:result) { call(unknown) }

        it "returns a Result::Error" do
          expect(result).to be_a(Pito::FollowUp::Result::Error)
        end

        it "uses the channel_list invalid_action message key" do
          expect(result.message_key).to eq("pito.follow_up.channel_list.errors.invalid_action")
        end

        it "includes the offending action in message_args" do
          expect(result.message_args).to include(action: unknown)
        end

        it "does NOT delegate to VerbDelegator" do
          result
          expect(Pito::FollowUp::VerbDelegator).not_to have_received(:call)
        end
      end
    end
  end
end
