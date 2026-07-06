# frozen_string_literal: true

require "rails_helper"

# ── Recognition matrix: #video_detail follow-up (DB mocked) ──────────────────
#
# RULE: every declared action is gated in — no exception.
# Verifies that each action VideoDetail declares does NOT fall through to
# invalid_action, and that the handler delegates to VerbDelegator for all of
# them.  DB is fully mocked (zero factories); VerbDelegator is stubbed to a
# sentinel so we test ROUTING, not execution.
#
# Subject: Pito::FollowUp::Handlers::VideoDetail
# Source event: instance_double(Event, payload: {"reply_target"=>"video_detail","video_id"=>42})
# Declared actions (12): rm · del · delete · reindex · link · unlink ·
#                        shinies · sync · publish · pub · unlist · schedule
#
# Bug contract: a declared action that hits invalid_action is a BUG — this spec
# will fail on that action and the failure is reported verbatim.

RSpec.describe "Dispatch matrix — #video_detail follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler) { Pito::FollowUp::Handlers::VideoDetail.new }

  # Source event carrying the video_detail reply_target and video_id 42.
  # No DB access — pure double.
  let(:source_event) do
    instance_double(
      Event,
      payload: { "reply_target" => "video_detail", "video_id" => 42 }
    )
  end

  let(:conversation) { instance_double(Conversation) }

  # Sentinel returned by VerbDelegator for every gated-in action.
  # Using consume: false so the double is stable under all delegated paths.
  let(:sentinel) { Pito::FollowUp::Result::Append.new(events: [], consume: false) }

  before do
    allow(Pito::FollowUp::VerbDelegator).to receive(:call).and_return(sentinel)
  end

  def call(rest)
    handler.call(event: source_event, rest:, conversation:)
  end

  # ── Registry ──────────────────────────────────────────────────────────────────

  describe "Registry" do
    it "resolves 'video_detail' to Handlers::VideoDetail" do
      expect(Pito::FollowUp::Registry.for("video_detail"))
        .to eq(Pito::FollowUp::Handlers::VideoDetail)
    end

    it "mode_for('video_detail') is :append" do
      expect(Pito::FollowUp::Registry.mode_for("video_detail")).to eq(:append)
    end

    it "actions_for('video_detail') contains the full declared set (all 15 — G122/G123 add game + at-a-glance)" do
      expect(Pito::FollowUp::Registry.actions_for("video_detail")).to match_array(
        %w[rm del delete reindex link unlink shinies sync publish pub unlist schedule analyze game at-a-glance]
      )
    end

    it "target is 'video_detail'" do
      expect(Pito::FollowUp::Handlers::VideoDetail.target).to eq("video_detail")
    end

    it "Matrix serves :append mode for video_detail" do
      expect(Pito::Dispatch::Matrix.mode_for("video_detail")).to eq(:append)
    end
  end

  # ── Declared actions — each must delegate, not hit invalid_action ─────────────
  #
  # Table: action word → representative rest string passed to handler.call.
  # All lookups are mocked via the VerbDelegator stub — no DB is touched.

  describe "declared actions → delegate to VerbDelegator (not invalid_action)" do
    {
      # delete aliases
      "rm"       => "rm",
      "del"      => "del",
      "delete"   => "delete",
      # reindex
      "reindex"  => "reindex",
      # link / unlink (with representative game ref)
      "link"     => "link to game #5",
      "unlink"   => "unlink from game #5",
      # shinies
      "shinies"  => "shinies",
      # sync (bare)
      "sync"     => "sync",
      # publish / pub / unlist (video-card ops, bare)
      "publish"  => "publish",
      "pub"      => "pub",
      "unlist"   => "unlist",
      # schedule (with representative args)
      "schedule" => "schedule tomorrow at 3pm"
    }.each do |action, rest_input|
      context "#{action.inspect} (rest: #{rest_input.inspect})" do
        subject(:result) { call(rest_input) }

        it "does NOT return a Result::Error (not invalid_action)" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to VerbDelegator.call with source_event + rest + conversation" do
          result
          expect(Pito::FollowUp::VerbDelegator).to have_received(:call).with(
            hash_including(source_event:, rest: rest_input, conversation:)
          )
        end

        it "returns the sentinel Append from VerbDelegator" do
          expect(result).to eq(sentinel)
        end
      end
    end
  end

  # ── Unknown action → invalid_action Error ────────────────────────────────────

  describe "unknown action → invalid_action Error" do
    subject(:result) { call("bogus") }

    it "returns a Result::Error" do
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the video_detail invalid_action message key" do
      expect(result.message_key).to eq("pito.follow_up.video_detail.errors.invalid_action")
    end

    it "includes the unknown action in message_args" do
      expect(result.message_args).to include(action: "bogus")
    end

    it "does NOT delegate to VerbDelegator" do
      result
      expect(Pito::FollowUp::VerbDelegator).not_to have_received(:call)
    end
  end
end
