# frozen_string_literal: true

require "rails_helper"

# ── Exhaustive recognition matrix: `game_detail` hashtag follow-up ─────────────
#
# RULE: every declared action is recognized — no exception.
# All DB mocked (zero factories). Source event via double with
# payload: { "reply_target" => "game_detail", "game_id" => 7 }.
#
# Delegated actions (rm/del/delete/reindex/link/unlink/shinies/sync):
#   → ToolDelegator; asserted gated-in + routes (not invalid_action).
# Retired actions (price/platform, Q16/Q16b — `update` owns field writes now):
#   → invalid_action Error, same as any other unknown token.
# Unknown action:
#   → invalid_action Error.
RSpec.describe "Dispatch matrix — game_detail follow-up (recognition, DB mocked)", type: :dispatch do
  before(:all) { Pito::FollowUp::Registry.register_all! }

  let(:handler)      { Pito::FollowUp::Handlers::GameDetail.new }
  let(:conversation) { double("Conversation") }

  # Stub game — resolved via ::Game.find_by(id: 7) inside resolve_game_from_event.
  let(:game_stub) do
    double("Game",
      id:    7,
      title: "Hollow Knight",
      "update!" => true)
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

    # Builder stub so direct handlers don't blow up.
    allow(Pito::MessageBuilder::Text).to receive(:call)
      .and_return({ "text" => "confirmed" })
  end

  # Convenience wrapper.
  def call(rest)
    handler.call(event: source_event, rest: rest, conversation: conversation)
  end

  # ── Registry — full action set ──────────────────────────────────────────────

  describe "Registry — actions_for('game_detail')" do
    subject(:actions) { Pito::FollowUp::Registry.actions_for("game_detail") }

    it "returns all 15 declared actions (G121/G123 add the segment verbs; vids alias of videos; @ai joined the anchored-reply roster; price/platform retired Q16/Q16b)" do
      expect(actions).to match_array(
        %w[rm del delete reindex link unlink shinies sync analyze at-a-glance videos vids similar channels @ai]
      )
    end

    %w[rm del delete reindex link unlink shinies sync].each do |action|
      it "includes #{action.inspect}" do
        expect(actions).to include(action)
      end
    end

    it "does NOT include price or platform (retired standalone tools, Q16/Q16b)" do
      expect(actions).not_to include("price", "platform")
    end
  end

  # ── Delegated actions → ToolDelegator ──────────────────────────────────────
  #
  # Each of these must be gated-in (declared) AND routed to ToolDelegator
  # (result is Append, not an invalid_action Error).

  describe "delegated actions" do
    DELEGATED_ACTIONS = %w[rm del delete reindex link unlink shinies sync].freeze

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

  # ── unknown action → invalid_action ────────────────────────────────────────

  describe "unknown action → invalid_action Error" do
    # `price`/`platform` retired as standalone tools (Q16/Q16b, 3.8.0) —
    # `price` used to be handled directly here (bypassing ToolDelegator); now
    # it's just another undeclared token, same as any other unknown word.
    %w[frobnicate edit show help update bogus price platform].each do |unknown|
      it "#{unknown.inspect} → Result::Error with invalid_action key" do
        result = call(unknown)
        expect(result).to be_a(Pito::FollowUp::Result::Error)
        expect(result.message_key).to eq("pito.follow_up.game_detail.errors.invalid_action")
      end
    end
  end
end
