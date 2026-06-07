# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::Enhanced do
  let(:game) { create(:game, title: "Portal 2") }

  describe ".call" do
    subject(:payload) { described_class.call(game) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html true" do
      expect(payload["html"]).to be true
    end

    it "includes the enhanced component markup in body" do
      expect(payload["body"]).to include("pito-game-enhanced-message")
    end

    it "stamps game_id in the payload" do
      expect(payload["game_id"]).to eq(game.id)
    end

    it "is NOT follow-up-able" do
      expect(Pito::FollowUp.followupable?(payload)).to be false
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
