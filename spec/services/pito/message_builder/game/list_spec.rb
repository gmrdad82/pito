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

    it "uses the #-prefixed game id as the first cell and title as the second cell" do
      rows = payload["table_rows"]
      expect(rows.map { |r| r[:cells][0][:text] }).to include("##{lies.id}", "##{zelda.id}")
      expect(rows.map { |r| r[:cells][1][:text] }).to include("Lies of P", "Tears of the Kingdom")
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

  describe ".call with columns: [:genre, :year]" do
    let(:genre)  { create(:genre, name: "Action") }
    let!(:game)  { create(:game, title: "Devil May Cry", release_year: 2001) }
    let!(:_link) { create(:game_genre, game: game, genre: genre) }

    let(:games) { ::Game.includes(:genres).order(:title) }

    subject(:payload) { described_class.call(games, conversation: conversation, columns: [ :genre, :year ]) }

    it "sets table_heading to [#, Game, Genre, Year]" do
      expect(payload["table_heading"]).to eq([ "#", "Game", "Genre", "Year" ])
    end

    it "returns 4 cells per row" do
      expect(payload["table_rows"].first[:cells].size).to eq(4)
    end

    it "includes the genre name in the third cell" do
      genre_text = payload["table_rows"].first[:cells][2][:text]
      expect(genre_text).to include("Action")
    end

    it "includes the release year in the fourth cell" do
      year_text = payload["table_rows"].first[:cells][3][:text]
      expect(year_text).to eq("2001")
    end
  end

  describe ".call with columns: [] (default)" do
    let(:games) { ::Game.order(:title) }

    subject(:payload) { described_class.call(games, conversation: conversation) }

    it "has heading [# Game] with no extra columns" do
      expect(payload["table_heading"]).to eq([ "#", "Game" ])
    end

    it "returns 2 cells per row" do
      row = payload["table_rows"].first
      expect(row[:cells].size).to eq(2)
    end

    it "first cell is cyan/right aligned id" do
      cell = payload["table_rows"].first[:cells][0]
      expect(cell[:class]).to include("text-cyan")
    end

    it "second cell has text-fg class" do
      cell = payload["table_rows"].first[:cells][1]
      expect(cell[:class]).to eq("text-fg")
    end
  end
end
