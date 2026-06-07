# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::ResyncConfirmation do
  let(:conversation) { create(:conversation) }
  let(:game) { create(:game, title: "Portal 2") }

  describe ".call" do
    subject(:payload) { described_class.call(game, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "has command of game_resync" do
      expect(payload["command"]).to eq("game_resync")
    end

    it "has html false" do
      expect(payload["html"]).to be false
    end

    it "includes the game title in body" do
      expect(payload["body"]).to include("Portal 2")
    end

    it "stamps game_id in the payload" do
      expect(payload["game_id"]).to eq(game.id)
    end

    it "stamps game_title in the payload" do
      expect(payload["game_title"]).to eq(game.title)
    end

    it "is follow-up-able with target confirmation" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
      expect(payload["reply_target"]).to eq("confirmation")
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
