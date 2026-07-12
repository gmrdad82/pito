# frozen_string_literal: true

require "rails_helper"

# ── Exhaustive recognition matrix: `game_detail` hashtag follow-up ─────────────
#
# RULE: every declared action is recognized — no exception.
# All DB mocked (zero factories). Source event via double with
# payload: { "reply_target" => "game_detail", "game_id" => 7 }.
#
# Delegated actions (rm/del/delete/reindex/link/unlink/platform/shinies/sync):
#   → ToolDelegator; asserted gated-in + routes (not invalid_action).
# Direct actions (footage, price):
#   → handled inline; asserted Append with correct effect; stubs ::Game.find_by.
# Unknown action:
#   → invalid_action Error.
RSpec.describe "Dispatch matrix — game_detail follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler)      { Pito::FollowUp::Handlers::GameDetail.new }
  let(:conversation) { double("Conversation") }

  # Stub game — resolved via ::Game.find_by(id: 7) inside resolve_game_from_event.
  let(:game_stub) do
    double("Game",
      id:            7,
      title:         "Hollow Knight",
      footage_hours: BigDecimal("5.0"),
      price:         BigDecimal("29.99"),
      "update!" =>   true)
  end

  # Source event with correct payload (no DB, no factories).
  let(:source_event) do
    double("Event", payload: { "reply_target" => "game_detail", "game_id" => 7 })
  end

  # Canned Append returned by the ToolDelegator stub.
  let(:delegated_append) do
    Pito::FollowUp::Result::Append.new(
      events: [ { kind: :system, payload: { "text" => "delegated" } } ]
    )
  end

  before do
    # DB: always resolve game 7.
    allow(::Game).to receive(:find_by).with(id: 7).and_return(game_stub)

    # ToolDelegator stub — delegated actions hit this.
    allow(Pito::FollowUp::ToolDelegator).to receive(:call).and_return(delegated_append)

    # Builder / formatter stubs so direct handlers don't blow up.
    allow(Pito::MessageBuilder::Footage::Snippet).to receive(:call)
      .and_return({ "text" => "ffprobe one-liner" })
    allow(Pito::MessageBuilder::Text).to receive(:call)
      .and_return({ "text" => "confirmed" })
    allow(Pito::Formatter::FootageHours).to receive(:call).and_return("5h")
    allow(Pito::Formatter::Price).to receive(:call).and_return("€29.99")
  end

  # Convenience wrapper.
  def call(rest)
    handler.call(event: source_event, rest: rest, conversation: conversation)
  end

  # ── Registry — full action set ──────────────────────────────────────────────

  describe "Registry — actions_for('game_detail')" do
    subject(:actions) { Pito::FollowUp::Registry.actions_for("game_detail") }

    it "returns all 17 declared actions (G121/G123 add the segment verbs; vids alias of videos)" do
      expect(actions).to match_array(
        %w[rm del delete reindex link unlink footage platform price shinies sync analyze at-a-glance videos vids similar channels]
      )
    end

    %w[rm del delete reindex link unlink footage platform price shinies sync].each do |action|
      it "includes #{action.inspect}" do
        expect(actions).to include(action)
      end
    end
  end

  # ── Delegated actions → ToolDelegator ──────────────────────────────────────
  #
  # Each of these must be gated-in (declared) AND routed to ToolDelegator
  # (result is Append, not an invalid_action Error).

  describe "delegated actions" do
    DELEGATED_ACTIONS = %w[rm del delete reindex link unlink platform shinies sync].freeze

    DELEGATED_ACTIONS.each do |action|
      describe action.inspect do
        subject(:result) { call(action) }

        it "is declared in actions_for (gated in)" do
          expect(Pito::FollowUp::Registry.actions_for("game_detail")).to include(action)
        end

        it "returns Result::Append (routes to ToolDelegator, not invalid_action)" do
          expect(result).to be_a(Pito::FollowUp::Result::Append)
        end

        it "does NOT return invalid_action Error" do
          expect(result).not_to be_a(Pito::FollowUp::Result::Error)
        end

        it "calls ToolDelegator.call with source_event and rest" do
          expect(Pito::FollowUp::ToolDelegator).to receive(:call).with(
            hash_including(source_event: source_event, rest: action, conversation: conversation)
          ).and_return(delegated_append)
          result
        end
      end
    end
  end

  # ── footage — direct handler ────────────────────────────────────────────────

  describe "'footage' — direct handler" do
    it "is declared in actions_for (gated in)" do
      expect(Pito::FollowUp::Registry.actions_for("game_detail")).to include("footage")
    end

    describe "footage <hours> — bare form" do
      subject(:result) { call("footage 3") }

      it "returns Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "calls game_stub.update! with footage_hours (sets hours on game 7)" do
        expect(game_stub).to receive(:update!).with(footage_hours: anything)
        result
      end

      it "does NOT delegate to ToolDelegator" do
        expect(Pito::FollowUp::ToolDelegator).not_to receive(:call)
        result
      end

      it "appends a :system kind event" do
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    describe "footage update <hours> — explicit update token" do
      subject(:result) { call("footage update 3") }

      it "returns Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "calls game_stub.update! (strips leading 'update' token)" do
        expect(game_stub).to receive(:update!).with(footage_hours: anything)
        result
      end

      it "does NOT delegate to ToolDelegator" do
        expect(Pito::FollowUp::ToolDelegator).not_to receive(:call)
        result
      end
    end

    describe "footage snippet — game-agnostic snippet form" do
      subject(:result) { call("footage snippet") }

      it "returns Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "calls Footage::Snippet.call (renders the ffprobe one-liner)" do
        expect(Pito::MessageBuilder::Footage::Snippet).to receive(:call)
        result
      end

      it "does NOT call ::Game.find_by (game-agnostic path)" do
        expect(::Game).not_to receive(:find_by)
        result
      end

      it "does NOT delegate to ToolDelegator" do
        expect(Pito::FollowUp::ToolDelegator).not_to receive(:call)
        result
      end

      it "appends a :system kind event" do
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    describe "footage (no hours) — missing argument" do
      subject(:result) { call("footage") }

      it "returns Result::Error" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "uses the missing_hours key" do
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.missing_hours")
      end
    end

    describe "footage -3 (negative value) — invalid hours" do
      subject(:result) { call("footage -3") }

      it "returns Result::Error" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "uses the missing_hours key" do
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.missing_hours")
      end
    end

    describe "footage bogus (non-numeric value) — invalid hours" do
      subject(:result) { call("footage bogus") }

      it "returns Result::Error with missing_hours key" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.missing_hours")
      end
    end

    describe "game not found during footage set" do
      before do
        allow(::Game).to receive(:find_by).with(id: 7).and_return(nil)
      end

      it "returns Result::Error with game_not_found key" do
        result = call("footage 3")
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.game_not_found")
      end
    end
  end

  # ── price — direct handler ──────────────────────────────────────────────────

  describe "'price' — direct handler" do
    it "is declared in actions_for (gated in)" do
      expect(Pito::FollowUp::Registry.actions_for("game_detail")).to include("price")
    end

    describe "price set 40 — explicit set form" do
      subject(:result) { call("price set 40") }

      it "returns Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "calls game_stub.update! with a price value" do
        expect(game_stub).to receive(:update!).with(price: BigDecimal("40.00"))
        result
      end

      it "does NOT delegate to ToolDelegator" do
        expect(Pito::FollowUp::ToolDelegator).not_to receive(:call)
        result
      end

      it "appends a :system kind event" do
        expect(result.events.first[:kind]).to eq(:system)
      end
    end

    describe "price 40 — implicit form (no 'set' keyword)" do
      subject(:result) { call("price 40") }

      it "returns Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "calls game_stub.update! with a price value" do
        expect(game_stub).to receive(:update!).with(price: BigDecimal("40.00"))
        result
      end

      it "does NOT delegate to ToolDelegator" do
        expect(Pito::FollowUp::ToolDelegator).not_to receive(:call)
        result
      end
    end

    describe "price unset — clear price to NULL" do
      subject(:result) { call("price unset") }

      it "returns Result::Append" do
        expect(result).to be_a(Pito::FollowUp::Result::Append)
      end

      it "calls game_stub.update! with price: nil" do
        expect(game_stub).to receive(:update!).with(price: nil)
        result
      end

      it "does NOT delegate to ToolDelegator" do
        expect(Pito::FollowUp::ToolDelegator).not_to receive(:call)
        result
      end
    end

    describe "price set (no amount) — missing argument" do
      subject(:result) { call("price set") }

      it "returns Result::Error" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "uses the missing_price key" do
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.missing_price")
      end
    end

    describe "price (bare, no amount) — missing argument" do
      subject(:result) { call("price") }

      it "returns Result::Error" do
        expect(result).to be_a(Pito::FollowUp::Result::Error)
      end

      it "uses the missing_price key" do
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.missing_price")
      end
    end

    describe "game not found during price set" do
      before do
        allow(::Game).to receive(:find_by).with(id: 7).and_return(nil)
      end

      it "returns Result::Error with game_not_found key" do
        result = call("price set 9.99")
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.game_not_found")
      end
    end
  end

  # ── unknown action → invalid_action ────────────────────────────────────────

  describe "unknown action → invalid_action Error" do
    %w[frobnicate edit show help update bogus].each do |unknown|
      it "#{unknown.inspect} → Result::Error with invalid_action key" do
        result = call(unknown)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.invalid_action")
      end
    end
  end
end
