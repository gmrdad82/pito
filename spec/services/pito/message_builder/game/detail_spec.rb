# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::Detail do
  let(:conversation) { create(:conversation) }
  let(:game) { create(:game, title: "Portal 2", summary: "A puzzle game.") }

  describe ".call" do
    subject(:payload) { described_class.call(game, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    it "includes the game title in body" do
      expect(payload["body"]).to include("Portal 2")
    end

    it "includes the rendered card HTML in body" do
      expect(payload["body"]).to include("pito-game-detail")
    end

    it "is follow-up-able" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
    end

    it "has reply_target of game_detail" do
      expect(payload["reply_target"]).to eq("game_detail")
    end

    it "includes the witty intro with the game title in body" do
      expect(payload["body"]).to include("Portal 2")
      # Intro now lives inside the card's left column, with a timestamp slot.
      expect(payload["body"]).to include("pito-game-detail__intro")
      expect(payload["body"]).to include("data-pito-ts-slot")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "stamps game_id in the payload" do
      expect(payload["game_id"]).to eq(game.id)
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
