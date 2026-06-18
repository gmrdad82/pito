# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::StatsPlaceholder do
  let(:game) { create(:game, title: "Hollow Knight") }

  describe ".call" do
    subject(:payload) { described_class.call(game) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "has a body key" do
      expect(payload).to have_key("body")
    end

    it "body contains the game title" do
      expect(payload["body"]).to include("Hollow Knight")
    end

    it "is an HTML payload (the Enhanced slot always renders HTML)" do
      expect(payload["html"]).to be(true)
      expect(payload["body"]).to include("pito-game-stats-placeholder-message")
    end

    it "is NOT follow-up-able" do
      expect(Pito::FollowUp.followupable?(payload)).to be(false)
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
