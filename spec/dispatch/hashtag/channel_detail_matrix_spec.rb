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
# DESTINATION_MAP (channel_detail):
#   "channel" / "youtube" / "yt" → :channel destination
#   "studio"                     → :studio  destination
#   anything else / bare         → needs_destination Error
#
# Routing in ChannelDetail#call:
#   "sync"               → VerbDelegator (re-sync source channel)
#   "visit channel"      → DIRECT: resolves channel → Result::Append (:channel)
#   "visit youtube"      → DIRECT: synonym for channel → Result::Append (:channel)
#   "visit yt"           → DIRECT: synonym for channel → Result::Append (:channel)
#   "visit studio"       → DIRECT: resolves channel → Result::Append (:studio)
#   "visit"              → needs_destination Error (no dest word)
#   "visit <unknown>"    → needs_destination Error (unrecognised dest)
#   channel missing      → channel_not_found Error
#   unknown action       → invalid_action Error (returned directly, no VerbDelegator)
#
# DB stubs:  ::Channel.find_by(id: 9) → channel_stub.
# Builder stub: Pito::MessageBuilder::Channel::Visit.call → visit_payload.
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

  let(:channel_stub) do
    double("Channel", id: 9, handle: "@alpha", youtube_channel_id: "UCabc")
  end

  # Canned payload returned by the stubbed Visit builder.
  let(:visit_payload) do
    { "body" => "<visit/>", "channel_id" => 9, "visit_state" => "visiting", "visit_destination" => "channel" }
  end

  # Sentinel returned by VerbDelegator for sync.
  let(:sentinel) { Pito::FollowUp::Result::Append.new(events: [], consume: false) }

  before do
    allow(::Channel).to receive(:find_by).with(id: 9).and_return(channel_stub)
    allow(Pito::MessageBuilder::Channel::Visit).to receive(:call).and_return(visit_payload)
    allow(Pito::FollowUp::VerbDelegator).to receive(:call).and_return(sentinel)
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

    it "actions_for('channel_detail') contains the declared set (segment verbs joined in G123)" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to match_array(%w[visit sync analyze at-a-glance videos vids games shinies])
    end

    it "is not internal (appears in help and suggestions)" do
      expect(Pito::FollowUp::Handlers::ChannelDetail.internal?).to be false
    end
  end

  # ── visit <destination> — DIRECT handler (not VerbDelegator) ──────────────────
  #
  # DESTINATION_MAP maps "channel" / "youtube" / "yt" → :channel; "studio" → :studio.

  describe "'visit' — direct handler, DESTINATION_MAP resolution" do
    {
      "channel" => :channel,
      "youtube" => :channel,
      "yt"      => :channel,
      "studio"  => :studio
    }.each do |dest_word, expected_destination|
      context "visit #{dest_word.inspect} → #{expected_destination}" do
        subject(:result) { call("visit #{dest_word}") }

        it "returns a Result::Append (not an Error)" do
          expect(result).to be_a(Pito::FollowUp::Result::Append)
        end

        it "does NOT return an invalid_action Error" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "does NOT delegate to VerbDelegator" do
          result
          expect(Pito::FollowUp::VerbDelegator).not_to have_received(:call)
        end

        it "resolves channel via ::Channel.find_by(id: 9)" do
          result
          expect(::Channel).to have_received(:find_by).with(id: 9)
        end

        it "calls Visit builder with #{expected_destination} destination" do
          result
          expect(Pito::MessageBuilder::Channel::Visit).to have_received(:call)
            .with(channel_stub, conversation:, destination: expected_destination)
        end

        it "appends one event with kind 'system'" do
          expect(result.events.size).to eq(1)
          expect(result.events.first[:kind]).to eq(:system)
        end

        it "event payload is the stubbed visit_payload" do
          expect(result.events.first[:payload]).to eq(visit_payload)
        end
      end
    end
  end

  # ── bare visit (no destination) → needs_destination Error ─────────────────────

  describe "bare 'visit' (no destination word) → needs_destination Error" do
    subject(:result) { call("visit") }

    it "returns a Result::Error" do
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the needs_destination message key" do
      expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.needs_destination")
    end

    it "does NOT call VerbDelegator" do
      result
      expect(Pito::FollowUp::VerbDelegator).not_to have_received(:call)
    end

    it "does NOT call Visit builder (error returned before resolution)" do
      result
      expect(Pito::MessageBuilder::Channel::Visit).not_to have_received(:call)
    end
  end

  # ── unknown destination word → needs_destination Error ────────────────────────

  describe "visit <unknown_dest> → needs_destination Error" do
    %w[tiktok twitch twitter home dashboard foo].each do |bad_dest|
      it "visit #{bad_dest.inspect} → needs_destination Error" do
        result = call("visit #{bad_dest}")
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.needs_destination")
      end

      it "visit #{bad_dest.inspect} does NOT call Visit builder" do
        call("visit #{bad_dest}")
        expect(Pito::MessageBuilder::Channel::Visit).not_to have_received(:call)
      end
    end
  end

  # ── channel not found during visit ────────────────────────────────────────────

  describe "channel not found via ::Channel.find_by → channel_not_found Error" do
    before { allow(::Channel).to receive(:find_by).with(id: 9).and_return(nil) }

    it "returns a Result::Error" do
      result = call("visit channel")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the channel_not_found message key" do
      result = call("visit channel")
      expect(result.message_key).to eq("pito.follow_up.channel_detail.errors.channel_not_found")
    end

    it "does NOT call Visit builder when channel is missing" do
      call("visit channel")
      expect(Pito::MessageBuilder::Channel::Visit).not_to have_received(:call)
    end
  end

  # ── sync — delegates to VerbDelegator ─────────────────────────────────────────

  describe "'sync' — delegates to VerbDelegator" do
    subject(:result) { call("sync") }

    it "is declared in actions_for('channel_detail')" do
      expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include("sync")
    end

    it "does NOT return a Result::Error (not invalid_action)" do
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "delegates to VerbDelegator.call with source_event, rest, conversation" do
      result
      expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
        hash_including(source_event:, rest: "sync", conversation:)
      )
    end

    it "returns the sentinel Append from VerbDelegator" do
      expect(result).to eq(sentinel)
    end

    it "does NOT call Visit builder (sync is not a visit)" do
      result
      expect(Pito::MessageBuilder::Channel::Visit).not_to have_received(:call)
    end
  end

  # ── declared segment verbs delegate to VerbDelegator ─────────────────────────
  #
  # games / videos / vids / shinies / at-a-glance are declared for channel_detail
  # in verbs.yml, so they route to the matrix-gated VerbDelegator (they were
  # silently rejected before the hardcoded-gate removal).
  describe "declared segment verbs → delegate to VerbDelegator" do
    %w[games videos vids shinies at-a-glance].each do |verb|
      context verb.inspect do
        subject(:result) { call(verb) }

        it "is declared in actions_for('channel_detail')" do
          expect(Pito::FollowUp::Registry.actions_for("channel_detail")).to include(verb)
        end

        it "does NOT return an invalid_action Error" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to VerbDelegator with the verb as rest" do
          result
          expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
            hash_including(source_event:, rest: verb, conversation:)
          )
        end
      end
    end
  end

  # ── Unknown action → invalid_action Error ─────────────────────────────────────
  #
  # Verbs NOT declared for channel_detail in verbs.yml are rejected with
  # invalid_action by the config-driven gate — NOT via VerbDelegator.

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

        it "does NOT call VerbDelegator" do
          result
          expect(Pito::FollowUp::VerbDelegator).not_to have_received(:call)
        end
      end
    end
  end
end
