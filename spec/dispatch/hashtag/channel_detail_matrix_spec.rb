# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: channel_detail hashtag follow-up (recognition, DB mocked) ─
#
# RULE: every declared action is gated in — no exception.
# All DB mocked (zero factories). Source event carries reply_target "channel_detail"
# and channel_id: 9.
#
# Target: "channel_detail", mode: :append
# Declared actions: "visit", "sync"
#
# Routing in ChannelDetail#call:
#   "sync"    → ToolDelegator (re-sync source channel)
#   "visit …" → ToolDelegator too (T9: the old DESTINATION_MAP special case
#               retired — visit is now config-declared (tools.yml
#               visit.reply.targets.channel_detail) and reaches
#               Pito::Chat::Handlers::Visit via ToolDelegator → Router, exactly
#               like every other reply tool this card accepts). The destination
#               vocabulary + legacy :channel mapping now live entirely in that
#               handler — see spec/lib/pito/chat/handlers/visit_spec.rb and
#               spec/dispatch/reply_binding_spec.rb for that coverage.
#   unknown action → invalid_action Error (returned directly, no ToolDelegator)
#
# Bug contract: a declared action that returns invalid_action is a BUG.
RSpec.describe "Dispatch matrix — #channel_detail follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler) { Pito::FollowUp::Handlers::ChannelDetail.new }

  let(:source_event) do
    instance_double(
      Event,
      payload: { "reply_target" => "channel_detail", "channel_id" => 9 }
    )
  end

  let(:conversation) { instance_double(Conversation) }

  # Sentinel returned by ToolDelegator for every delegated action.
  let(:sentinel) { Pito::FollowUp::Result::Append.new(events: [], consume: false) }

  before do
    allow(Pito::FollowUp::ToolDelegator).to receive(:call).and_return(sentinel)
  end

  def call(rest)
    handler.call(event: source_event, rest:, conversation:)
  end

  # ── Registry ──────────────────────────────────────────────────────────────────

  describe "Registry" do
    it "resolves 'channel_detail' to Handlers::ChannelDetail" do
      expect(Pito::FollowUp::Registry.for("channel_detail"))
        .to eq(Pito::FollowUp::Handlers::ChannelDetail)
    end

    it "mode_for('channel_detail') is :append" do
      expect(Pito::FollowUp::Registry.mode_for("channel_detail")).to eq(:append)
    end

    it "target is 'channel_detail'" do
      expect(Pito::FollowUp::Handlers::ChannelDetail.target).to eq("channel_detail")
    end

    it "Matrix serves :append mode for channel_detail" do
      expect(Pito::Dispatch::Matrix.mode_for("channel_detail")).to eq(:append)
    end

    it "Matrix advertises visit, sync, and analyze for channel_detail" do
      expect(Pito::Dispatch::Matrix.actions_for("channel_detail")).to include("visit", "sync", "analyze")
    end

    it "actions_for('channel_detail') contains the declared set (segment verbs joined in G123; @ai joined the anchored-reply roster)" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to match_array(%w[visit sync analyze at-a-glance videos vids games shinies @ai])
    end

    it "is not internal (appears in help and suggestions)" do
      expect(Pito::FollowUp::Handlers::ChannelDetail.internal?).to be false
    end
  end

  # ── visit — delegates to ToolDelegator (T9: config-declared dispatch) ────────
  #
  # Destination parsing/resolution now lives entirely in Chat::Handlers::Visit,
  # reached via the SAME ToolDelegator → Router path every other declared reply
  # tool on this card takes — see that handler's class header for the
  # destination vocabulary + legacy :channel mapping this replaces, and
  # spec/lib/pito/chat/handlers/visit_spec.rb / spec/dispatch/reply_binding_spec.rb
  # for the behavioral coverage that used to live here.

  describe "'visit' — delegates to ToolDelegator" do
    subject(:result) { call("visit channel") }

    it "is declared in actions_for('channel_detail')" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include("visit")
    end

    it "does NOT return a Result::Error (not invalid_action)" do
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "delegates to ToolDelegator.call with source_event, rest, conversation" do
      result
      expect(Pito::FollowUp::ToolDelegator).to have_received(:call).with(
        hash_including(source_event:, rest: "visit channel", conversation:)
      )
    end

    it "returns the sentinel Append from ToolDelegator" do
      expect(result).to eq(sentinel)
    end
  end

  # ── sync — delegates to ToolDelegator ─────────────────────────────────────────

  describe "'sync' — delegates to ToolDelegator" do
    subject(:result) { call("sync") }

    it "is declared in actions_for('channel_detail')" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include("sync")
    end

    it "does NOT return a Result::Error (not invalid_action)" do
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "delegates to ToolDelegator.call with source_event, rest, conversation" do
      result
      expect(Pito::FollowUp::ToolDelegator).to have_received(:call).with(
        hash_including(source_event:, rest: "sync", conversation:)
      )
    end

    it "returns the sentinel Append from ToolDelegator" do
      expect(result).to eq(sentinel)
    end
  end

  # ── declared segment verbs delegate to ToolDelegator ─────────────────────────
  #
  # games / videos / vids / shinies / at-a-glance are declared for channel_detail
  # in tools.yml, so they route to the matrix-gated ToolDelegator (they were
  # silently rejected before the hardcoded-gate removal).
  describe "declared segment verbs → delegate to ToolDelegator" do
    %w[games videos vids shinies at-a-glance].each do |verb|
      context verb.inspect do
        subject(:result) { call(verb) }

        it "is declared in actions_for('channel_detail')" do
          expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include(verb)
        end

        it "does NOT return an invalid_action Error" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to ToolDelegator with the verb as rest" do
          result
          expect(Pito::FollowUp::ToolDelegator).to have_received(:call).with(
            hash_including(source_event:, rest: verb, conversation:)
          )
        end
      end
    end
  end

  # ── Unknown action → invalid_action Error ─────────────────────────────────────
  #
  # Verbs NOT declared for channel_detail in tools.yml are rejected with
  # invalid_action by the config-driven gate — NOT via ToolDelegator.

  describe "unknown action → invalid_action Error" do
    %w[open show delete rm link unlink reindex bogus update help].each do |unknown|
      context unknown.inspect do
        subject(:result) { call(unknown) }

        it "returns a Result::Error" do
          expect(result).to be_a(Pito::FollowUp::Result::Error)
        end

        it "uses the channel_detail invalid_action message key" do
          expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.invalid_action")
        end

        it "includes the offending action in message_args" do
          expect(result.message_args).to include(action: unknown)
        end

        it "does NOT call ToolDelegator" do
          result
          expect(Pito::FollowUp::ToolDelegator).not_to have_received(:call)
        end
      end
    end
  end
end
