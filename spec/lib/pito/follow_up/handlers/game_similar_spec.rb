# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::GameSimilar do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:game)        { create(:game, title: "Lies of P") }

  # A game_similar source event — the shown game's id in the payload.
  let(:event) do
    instance_double(Event, payload: {
      "reply_target" => "game_similar",
      "game_id"      => game.id
    })
  end

  it "registers for the game_similar target" do
    expect(described_class.target).to eq("game_similar")
  end

  it "Matrix serves :append mode for game_similar" do
    expect(Pito::Dispatch::Matrix.mode_for("game_similar")).to eq(:append)
  end

  it "Matrix advertises 'show' for game_similar" do
    expect(Pito::Dispatch::Matrix.actions_for("game_similar")).to include("show")
  end

  describe "`@ai <text>` — anchored reply (owner-scoped roster)" do
    let(:ai_event) { instance_double(Event, id: 4247, payload: event.payload) }

    it "delegates to Chat::Handlers::Ai via ToolDelegator: a pending :ai event anchored on this strip" do
      result = handler.call(event: ai_event, rest: "@ai are any of these actually similar", conversation:)

      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
      pending = result.events.first
      expect(pending[:kind]).to eq(:ai)
      expect(pending[:payload]["status"]).to eq("pending")
      expect(pending[:payload]["prompt"]).to eq("are any of these actually similar")
      expect(pending[:payload]["anchor_event_id"]).to eq(4247)
    end
  end

  describe "#call — show <id>" do
    it "returns a Result::Append for a known game id" do
      result = handler.call(event:, rest: "show #{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "routes to the game branch: first event is :system game_detail" do
      result = handler.call(event:, rest: "show #{game.id}", conversation:)
      first  = result.events.first
      expect(first[:kind]).to eq(:system)
      expect(first[:payload]["reply_target"]).to eq("game_detail")
      expect(first[:payload]["game_id"]).to eq(game.id)
    end

    it "resolves by SIMILAR game id, not the source game — free-chat dispatch ignores source game_id" do
      other_game = create(:game, title: "Sekiro")
      result     = handler.call(event:, rest: "show #{other_game.id}", conversation:)
      first      = result.events.first
      expect(first[:payload]["game_id"]).to eq(other_game.id)
    end

    it "accepts a hash-prefixed id (#N)" do
      result = handler.call(event:, rest: "show ##{game.id}", conversation:)
      expect(result.events.first[:payload]["game_id"]).to eq(game.id)
    end

    it "returns a not-found Ok (consume: false) for an unknown id" do
      result = handler.call(event:, rest: "show 999999", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
    end

    it "resolves a non-numeric ref by title now that `show` accepts titles (P36)" do
      # The follow-up dispatches `show game <ref>` as free-chat, so it inherits
      # `show`'s P36 title resolution: "lies of p" matches the "Lies of P" game
      # above and opens it (consume: true), no longer id-only.
      result = handler.call(event:, rest: "show lies of p", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(true)
    end

    it "returns a not-found Ok for a ref matching no id and no title" do
      result = handler.call(event:, rest: "show no such game anywhere", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
    end
  end

  describe "#call — invalid action" do
    it "returns a Result::Error for an unrecognised action" do
      result = handler.call(event:, rest: "delete #{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.game_similar.errors.invalid_action")
    end

    it "returns a Result::Error for an empty action" do
      result = handler.call(event:, rest: "", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
    end
  end
end
