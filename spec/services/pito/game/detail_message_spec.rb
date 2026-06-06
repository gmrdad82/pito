# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::DetailMessage do
  let(:conversation) { create(:conversation) }
  let(:game) { create(:game, title: "Portal 2", summary: "A puzzle game.") }

  describe ".call" do
    subject(:payload) { described_class.call(game, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "sets html: true" do
      expect(payload["html"]).to be true
    end

    it "includes the game title in body" do
      expect(payload["body"]).to include("Portal 2")
    end

    it "includes the rendered card HTML in body" do
      # The card renders the game title inside a div with class pito-game-detail
      expect(payload["body"]).to include("pito-game-detail")
    end

    it "is follow-up-able" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
    end

    it "has reply_target of game_detail" do
      expect(payload["reply_target"]).to eq("game_detail")
    end

    it "includes the witty intro with the game title in body" do
      # The copy sampler is deterministic in tests (returns first variant).
      # First variant: "Here's everything pito knows about %{title}."
      expect(payload["body"]).to include("Portal 2")
      # The intro is rendered in a <p> tag
      expect(payload["body"]).to include("<p")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end
  end
end
