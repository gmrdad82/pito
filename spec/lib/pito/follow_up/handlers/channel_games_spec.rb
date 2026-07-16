# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::FollowUp::Handlers::ChannelGames do
  subject(:handler) { described_class.new }

  let(:conversation) { Conversation.singleton }
  let!(:channel)     { create(:channel, handle: "@grid") }
  let!(:game)        { create(:game, title: "Hades") }

  # A channel_games source event — the shown channel's id in the payload.
  let(:event) do
    instance_double(Event, payload: {
      "reply_target" => "channel_games",
      "channel_id"   => channel.id
    })
  end

  it "registers for the channel_games target" do
    expect(described_class.target).to eq("channel_games")
  end

  it "Matrix serves :append mode for channel_games" do
    expect(Pito::Dispatch::Matrix.mode_for("channel_games")).to eq(:append)
  end

  it "Matrix advertises 'show' for channel_games" do
    expect(Pito::Dispatch::Matrix.actions_for("channel_games")).to include("show")
  end

  describe "#call — show <id>" do
    it "returns a Result::Append for a known game id" do
      result = handler.call(event:, rest: "show #{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
    end

    it "routes to the game branch: first event is :system game_detail (not the source channel)" do
      result = handler.call(event:, rest: "show #{game.id}", conversation:)
      first  = result.events.first
      expect(first[:kind]).to eq(:system)
      expect(first[:payload]["reply_target"]).to eq("game_detail")
      expect(first[:payload]["game_id"]).to eq(game.id)
    end

    it "accepts a hash-prefixed id (#N)" do
      result = handler.call(event:, rest: "show ##{game.id}", conversation:)
      expect(result.events.first[:payload]["game_id"]).to eq(game.id)
    end

    # 3.0.1 reconciliation fix: this free-chat re-dispatch has no follow_up
    # context (so title resolution still runs), but a ref matching neither an
    # id nor a title must stay the crisp not-found (consume: false) — never
    # leak into the NL gate (mirrors GameSimilar's equivalent example).
    it "returns a not-found Ok (consume: false) for a ref matching no id and no title" do
      result = handler.call(event:, rest: "show no such game anywhere", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Append)
      expect(result.consume).to be(false)
    end
  end

  describe "invalid action" do
    it "returns Result::Error with the channel_games invalid_action copy" do
      result = handler.call(event:, rest: "visit #{game.id}", conversation:)
      expect(result).to be_a(Pito::FollowUp::Result::Error)
      expect(result.message_key).to eq("pito.follow_up.channel_games.errors.invalid_action")
    end
  end
end
