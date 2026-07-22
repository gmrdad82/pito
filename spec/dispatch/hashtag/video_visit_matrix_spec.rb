# frozen_string_literal: true

require "rails_helper"

# ── Dispatch matrix: video_visit hashtag follow-up (recognition, DB mocked) ───
#
# All DB mocked (zero factories). Source event carries video_id: 9 and
# visit_destination in payload.
#
# Target:          "video_visit"
# Mode:            :mutate  (transforms event in place; no echo, no turn)
# Declared action: "consume"
# Internal:        true  ← never user-typeable; not in help or suggestions;
#                         no reply_handle stamped on the event
#
# video_visit is the RESULT card produced by the `visit` tool on any vid
# surface (video_detail / video_list / video_search / game_linked_videos). The
# pito--auto-visit Stimulus controller auto-clicks the hidden link once, then
# POSTs to Videos::VisitsController#consume, which routes "consume" here via
# the standard FollowUpDispatchJob mutation path.
#
# Routing in VideoVisit#call:
#   "consume" + video found    → Result::Mutation(kind: "system_follow_up")
#   "consume" + video absent   → video_not_found Error
#   unknown action             → invalid_action Error (returned directly)
#
# visit_destination preservation:
#   "studio"   → :studio   destination passed to builder
#   "youtube"  → :youtube  destination passed to builder
#   nil/other  → :youtube  (safe default)
#
# DB stubs:  ::Video.find_by(id: 9) → video_stub.
# Builder stub: Pito::MessageBuilder::Video::Visit.call → visited_payload.
#
# Bug contract: a declared action that returns invalid_action Error is a BUG.
RSpec.describe "Dispatch matrix — #video_visit follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler) { Pito::FollowUp::Handlers::VideoVisit.new }

  let(:video_stub) do
    double("Video", id: 9, title: "Boss Rush", youtube_video_id: "yt_abc")
  end

  # Canned payload returned by the stubbed Visit builder (visited state).
  let(:visited_payload) do
    { "body" => "<visited/>", "video_id" => 9, "visit_state" => "visited", "visit_destination" => "youtube" }
  end

  let(:conversation) { instance_double(Conversation) }

  before do
    allow(::Video).to receive(:find_by).with(id: 9).and_return(video_stub)
    allow(Pito::MessageBuilder::Video::Visit).to receive(:call).and_return(visited_payload)
  end

  # Build a source event with the given payload overrides.
  # Base payload: video_id 9 + visit_destination "youtube".
  def build_event(overrides = {})
    instance_double(
      Event,
      payload: { "video_id" => 9, "visit_destination" => "youtube" }.merge(overrides)
    )
  end

  def call(rest, source_event = build_event)
    handler.call(event: source_event, rest:, conversation:)
  end

  # ── Registry — internal handler ────────────────────────────────────────────────

  describe "Registry — internal handler" do
    it "resolves 'video_visit' to Handlers::VideoVisit" do
      expect(Pito::FollowUp::Registry.for("video_visit"))
        .to eq(Pito::FollowUp::Handlers::VideoVisit)
    end

    it "target is 'video_visit'" do
      expect(Pito::FollowUp::Handlers::VideoVisit.target).to eq("video_visit")
    end

    it "Matrix serves :mutate mode for video_visit (transforms event in place; no echo, no new turn)" do
      expect(Pito::Dispatch::Matrix.mode_for("video_visit")).to eq(:mutate)
    end

    it "mode_for('video_visit') is :mutate via Registry → Matrix" do
      expect(Pito::FollowUp::Registry.mode_for("video_visit")).to eq(:mutate)
    end

    it "is internal (never user-typeable; excluded from help and suggestions)" do
      expect(Pito::FollowUp::Handlers::VideoVisit.internal?).to be true
    end

    it "Matrix advertises only 'consume' for video_visit" do
      expect(Pito::Dispatch::Matrix.actions_for("video_visit")).to include("consume")
    end

    it "actions_for('video_visit') contains 'consume'" do
      expect(Pito::FollowUp::Registry.actions_for("video_visit")).to include("consume")
    end
  end

  # ── consume — declared action → Result::Mutation ──────────────────────────────

  describe "'consume' — declared action → Result::Mutation" do
    subject(:result) { call("consume") }

    it "returns a Result::Mutation" do
      expect(result).to be_a(Pito::FollowUp::Result::Mutation)
    end

    it "mutation kind is 'system_follow_up'" do
      expect(result.kind).to eq(:system_follow_up)
    end

    it "does NOT return a Result::Error" do
      expect(result).not_to be_a(Pito::FollowUp::Result::Error)
    end

    it "resolves video via ::Video.find_by(id: 9)" do
      result
      expect(::Video).to have_received(:find_by).with(id: 9)
    end

    it "calls Visit builder with video_stub and state: :visited" do
      result
      expect(Pito::MessageBuilder::Video::Visit).to have_received(:call)
        .with(video_stub, state: :visited, destination: anything)
    end

    it "mutation payload is the stubbed visited_payload" do
      expect(result.payload).to eq(visited_payload)
    end
  end

  # ── consume preserves visit_destination from the source event payload ─────────

  describe "'consume' — visit_destination preservation" do
    context "visit_destination: 'youtube' → destination :youtube" do
      it "calls Visit builder with destination: :youtube" do
        call("consume", build_event("visit_destination" => "youtube"))
        expect(Pito::MessageBuilder::Video::Visit).to have_received(:call)
          .with(video_stub, state: :visited, destination: :youtube)
      end
    end

    context "visit_destination: 'studio' → destination :studio" do
      it "calls Visit builder with destination: :studio" do
        call("consume", build_event("visit_destination" => "studio"))
        expect(Pito::MessageBuilder::Video::Visit).to have_received(:call)
          .with(video_stub, state: :visited, destination: :studio)
      end
    end

    context "visit_destination: nil → defaults to :youtube" do
      it "calls Visit builder with destination: :youtube (safe default)" do
        call("consume", build_event("visit_destination" => nil))
        expect(Pito::MessageBuilder::Video::Visit).to have_received(:call)
          .with(video_stub, state: :visited, destination: :youtube)
      end
    end

    context "visit_destination: unrecognised value → defaults to :youtube" do
      it "calls Visit builder with destination: :youtube" do
        call("consume", build_event("visit_destination" => "bogus"))
        expect(Pito::MessageBuilder::Video::Visit).to have_received(:call)
          .with(video_stub, state: :visited, destination: :youtube)
      end
    end
  end

  # ── consume — video not found ────────────────────────────────────────────────

  describe "'consume' — video not found → video_not_found Error" do
    before { allow(::Video).to receive(:find_by).with(id: 9).and_return(nil) }

    it "returns a Result::Error" do
      result = call("consume")
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end

    it "uses the video_not_found message key" do
      result = call("consume")
      expect(result.message_key).to eq("pito.follow_up.video_visit.errors.video_not_found")
    end

    it "does NOT call Visit builder when video is missing" do
      call("consume")
      expect(Pito::MessageBuilder::Video::Visit).not_to have_received(:call)
    end
  end

  # ── Unknown action → invalid_action Error ─────────────────────────────────────
  #
  # video_visit declares only "consume". Any other action returns invalid_action
  # directly (no ToolDelegator involvement — handler does not delegate).

  describe "unknown action → invalid_action Error" do
    %w[visit sync open show delete rm shinies bogus nope].each do |unknown|
      context unknown.inspect do
        subject(:result) { call(unknown) }

        it "returns a Result::Error" do
          expect(result).to be_a(Pito::FollowUp::Result::Error)
        end

        it "uses the video_visit invalid_action message key" do
          expect(result.message_key).to eq("pito.follow_up.video_visit.errors.invalid_action")
        end

        it "includes the offending action in message_args" do
          expect(result.message_args).to include(action: unknown)
        end

        it "does NOT call Visit builder" do
          result
          expect(Pito::MessageBuilder::Video::Visit).not_to have_received(:call)
        end
      end
    end
  end
end
