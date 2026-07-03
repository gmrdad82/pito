# frozen_string_literal: true

require "rails_helper"

# ── Recognition matrix: analyze_message hashtag follow-up (DB fully mocked) ───
#
# RULE: every declared action is recognized — no exception.
# DB fully mocked (zero factories). Source event is a plain double carrying the
# analyze payload structure the handler reads. MessageBuilder::Analyze::Message.rerender
# is stubbed to a sentinel so this spec tests ROUTING + ACCUMULATION, not builder output.
#
# Declared actions (2): with · without
# + unknown → invalid_action Error
# + empty metrics → no_metrics Error
#
# Accumulation: verified by asserting the args passed to rerender.
#
# Bug contract: a declared action that hits invalid_action is a BUG — this spec
# will fail on that action and the failure is reported verbatim.
RSpec.describe "Dispatch matrix — analyze_message follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler)      { Pito::FollowUp::Handlers::AnalyzeMessage.new }
  let(:conversation) { double("Conversation") }

  # Sentinel payload returned by the rerender stub.
  let(:sentinel_payload) do
    {
      "body"    => "<div>rerendered</div>",
      "html"    => true,
      "analyze" => { "status" => "ready", "with" => [], "without" => [] }
    }
  end

  # Build a source event double with an analyze marker at a given selection state.
  # `with_list` / `without_list` are String arrays (as stored in the jsonb marker).
  def analyze_event(with_list: [], without_list: [], kind: "system")
    double("Event",
      kind:    kind,
      payload: {
        "analyze" => {
          "status"   => "ready",
          "role"     => kind.to_s,
          "level"    => "vid",
          "with"     => with_list,
          "without"  => without_list,
          "scaffold" => { "views" => true, "comments" => true },
          "intro"    => "<span>Intro</span>"
        },
        "reply_handle" => "analyze-0001",
        "reply_target" => "analyze_message"
      }
    )
  end

  let(:source_event) { analyze_event }

  before do
    allow(Pito::MessageBuilder::Analyze::Message).to receive(:rerender).and_return(sentinel_payload)
  end

  def call(event: source_event, rest:)
    handler.call(event: event, rest: rest, conversation: conversation)
  end

  # ── Registry ────────────────────────────────────────────────────────────────

  describe "Registry" do
    it "resolves 'analyze_message' to Handlers::AnalyzeMessage" do
      expect(Pito::FollowUp::Registry.for("analyze_message"))
        .to eq(Pito::FollowUp::Handlers::AnalyzeMessage)
    end

    it "mode_for('analyze_message') is :mutate" do
      expect(Pito::FollowUp::Registry.mode_for("analyze_message")).to eq(:mutate)
    end

    it "actions_for('analyze_message') is exactly ['with', 'without']" do
      expect(Pito::FollowUp::Registry.actions_for("analyze_message"))
        .to match_array(%w[with without])
    end

    it "class target is 'analyze_message'" do
      expect(Pito::FollowUp::Handlers::AnalyzeMessage.target).to eq("analyze_message")
    end

    it "Matrix serves :mutate mode for analyze_message" do
      expect(Pito::Dispatch::Matrix.mode_for("analyze_message")).to eq(:mutate)
    end
  end

  # ── 'with' action ───────────────────────────────────────────────────────────

  describe "'with' action → Result::Mutation (not invalid_action)" do
    {
      "single metric"        => "with views",
      "comma-separated list" => "with views,comments",
      "space-separated list" => "with views comments",
      "aliased metric"       => "with comms"
    }.each do |desc, rest_input|
      context desc do
        subject(:result) { call(rest: rest_input) }

        it "returns Result::Mutation" do
          expect(result).to be_a(Pito::FollowUp::Result::Mutation)
        end

        it "is NOT a Result::Error (not invalid_action)" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to Message.rerender" do
          result
          expect(Pito::MessageBuilder::Analyze::Message).to have_received(:rerender)
        end
      end
    end
  end

  # ── 'without' action ─────────────────────────────────────────────────────────

  describe "'without' action → Result::Mutation (not invalid_action)" do
    {
      "single metric"        => "without views",
      "comma-separated list" => "without views,comments",
      "space-separated list" => "without views comments"
    }.each do |desc, rest_input|
      context desc do
        subject(:result) { call(rest: rest_input) }

        it "returns Result::Mutation" do
          expect(result).to be_a(Pito::FollowUp::Result::Mutation)
        end

        it "is NOT a Result::Error (not invalid_action)" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "delegates to Message.rerender" do
          result
          expect(Pito::MessageBuilder::Analyze::Message).to have_received(:rerender)
        end
      end
    end
  end

  # ── Mutation carries the source event's kind ─────────────────────────────────

  describe "Result::Mutation kind mirrors the source event" do
    it "kind is :system when source event kind is 'system'" do
      result = call(event: analyze_event(kind: "system"), rest: "with views")
      expect(result.kind).to eq(:system)
    end

    it "kind is :enhanced when source event kind is 'enhanced'" do
      result = call(event: analyze_event(kind: "enhanced"), rest: "with views")
      expect(result.kind).to eq(:enhanced)
    end
  end

  # ── Empty metrics → no_metrics Error ────────────────────────────────────────

  describe "empty metrics → no_metrics Error" do
    context "'with' with no metric tokens" do
      subject(:result) { call(rest: "with") }

      it "returns Result::Error" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "uses the no_metrics message key" do
        expect(result.message_key)
          .to eq("pito.follow_up.analyze_message.errors.no_metrics")
      end

      it "does NOT call rerender" do
        result
        expect(Pito::MessageBuilder::Analyze::Message).not_to have_received(:rerender)
      end
    end

    context "'without' with no metric tokens" do
      subject(:result) { call(rest: "without") }

      it "returns Result::Error" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "uses the no_metrics message key" do
        expect(result.message_key)
          .to eq("pito.follow_up.analyze_message.errors.no_metrics")
      end

      it "does NOT call rerender" do
        result
        expect(Pito::MessageBuilder::Analyze::Message).not_to have_received(:rerender)
      end
    end
  end

  # ── Accumulation ──────────────────────────────────────────────────────────────
  #
  # Verified by checking the with:/without: args that rerender receives.
  # See handler#accumulate for the rules:
  #   without X → exclude X (add to without, remove from with whitelist)
  #   with X    → re-include X (remove from without, extend active whitelist)

  describe "accumulation" do
    describe "'without views' from clean state (with: [], without: [])" do
      subject(:result) { call(event: analyze_event(with_list: [], without_list: []), rest: "without views") }

      it "returns Result::Mutation" do
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end

      it "calls rerender with without: [:views]" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(without: [ :views ]))
      end

      it "calls rerender with with: [] (no whitelist change)" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(with: []))
      end
    end

    describe "'with views' when views is excluded (with: [], without: ['views'])" do
      subject(:result) { call(event: analyze_event(with_list: [], without_list: [ "views" ]), rest: "with views") }

      it "returns Result::Mutation" do
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end

      it "calls rerender with without: [] (views removed from exclusion list)" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(without: []))
      end

      it "calls rerender with with: [] (whitelist not extended when originally empty)" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(with: []))
      end
    end

    describe "'with comments' when a whitelist is active (with: ['views'], without: [])" do
      subject(:result) { call(event: analyze_event(with_list: [ "views" ], without_list: []), rest: "with comments") }

      it "returns Result::Mutation" do
        expect(result).to be_a(Pito::FollowUp::Result::Mutation)
      end

      it "calls rerender with with: [:views, :comments] (extends active whitelist)" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(with: [ :views, :comments ]))
      end

      it "calls rerender with without: [] (nothing excluded)" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(without: []))
      end
    end

    describe "'without views' when views is in the whitelist (with: ['views'], without: [])" do
      subject(:result) { call(event: analyze_event(with_list: [ "views" ], without_list: []), rest: "without views") }

      it "calls rerender with with: [] (views removed from whitelist)" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(with: []))
      end

      it "calls rerender with without: [:views]" do
        result
        expect(Pito::MessageBuilder::Analyze::Message)
          .to have_received(:rerender).with(anything, hash_including(without: [ :views ]))
      end
    end
  end

  # ── Unknown action → invalid_action Error ───────────────────────────────────

  describe "unknown action → invalid_action Error" do
    %w[analyze show bogus edit help frobnicate].each do |unknown|
      context "#{unknown.inspect} (not declared)" do
        subject(:result) { call(rest: unknown) }

        it "returns Result::Error" do
          expect(result).to be_a(Pito::FollowUp::Result::Error)
        end

        it "uses the invalid_action message key" do
          expect(result.message_key)
            .to eq("pito.follow_up.analyze_message.errors.invalid_action")
        end

        it "includes the unknown action in message_args" do
          expect(result.message_args).to include(action: unknown)
        end

        it "does NOT return Result::Mutation" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Mutation)
        end

        it "does NOT call rerender" do
          result
          expect(Pito::MessageBuilder::Analyze::Message).not_to have_received(:rerender)
        end
      end
    end
  end
end
