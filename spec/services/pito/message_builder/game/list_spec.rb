# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::List do
  let(:conversation) { create(:conversation) }
  let!(:zelda) { create(:game, title: "Tears of the Kingdom") }
  let!(:lies)  { create(:game, title: "Lies of P") }

  describe ".call" do
    let(:games) { ::Game.order(:title) }

    subject(:payload) { described_class.call(games, conversation: conversation) }

    it "returns a Hash" do
      expect(payload).to be_a(Hash)
    end

    it "includes table_rows with each game" do
      expect(payload["table_rows"]).to be_present
      expect(payload["table_rows"].size).to eq(2)
    end

    it "uses the #-prefixed game id as key and title as value" do
      rows = payload["table_rows"]
      expect(rows.map { |r| r[:key] }).to include("##{lies.id}", "##{zelda.id}")
      expect(rows.map { |r| r[:value] }).to include("Lies of P", "Tears of the Kingdom")
    end

    it "includes the intro body with count" do
      expect(payload["body"]).to include("2")
    end

    it "is follow-up-able with target game_list" do
      expect(Pito::FollowUp.followupable?(payload)).to be true
      expect(payload["reply_target"]).to eq("game_list")
    end

    it "has a reply_handle in the payload" do
      expect(payload["reply_handle"]).to be_present
    end

    it "includes table_heading with # and Game labels" do
      expect(payload["table_heading"]).to eq([ "#", "Game" ])
    end

    it "renders without raising" do
      expect { payload }.not_to raise_error
    end
  end
end
