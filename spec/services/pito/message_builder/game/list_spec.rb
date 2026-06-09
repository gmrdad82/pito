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

    it "includes table_heading with # as a right-aligned hash and Game as a string" do
      expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Game" ])
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

    it "sets table_heading to [#-hash, Game, Genre, Year-hash]" do
      expect(payload["table_heading"]).to eq([
        { "text" => "#", "class" => "text-right" },
        "Game",
        "Genre",
        { "text" => "Year", "class" => "text-right" }
      ])
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

    it "has heading [#-hash, Game] with no extra columns" do
      expect(payload["table_heading"]).to eq([ { "text" => "#", "class" => "text-right" }, "Game" ])
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

  # ── Pluralization ────────────────────────────────────────────────────────────

  describe ".call — intro pluralization" do
    context "with 1 game" do
      let!(:solo) { create(:game, title: "Solo Game") }
      let(:games) { ::Game.where(id: solo.id) }

      subject(:payload) { described_class.call(games, conversation: conversation) }

      it "uses singular 'game' in the intro" do
        expect(payload["body"]).to include("1 game")
        expect(payload["body"]).not_to match(/1 games/)
      end
    end

    context "with 2 games" do
      let(:games) { ::Game.order(:title) }

      subject(:payload) { described_class.call(games, conversation: conversation) }

      it "uses plural 'games' in the intro" do
        expect(payload["body"]).to include("2 games")
      end
    end
  end

  # ── Full columns (all 6 with-cols) ────────────────────────────────────────────

  describe ".call with all 6 columns (developer, publisher, genre, platform, release_date, year)" do
    let(:genre)       { create(:genre, name: "Action") }
    let(:dev_co)      { create(:company, name: "Studio Dev") }
    let(:pub_co)      { create(:company, name: "Studio Pub") }

    let!(:game) do
      g = create(:game, title: "Full Game", release_year: 2023,
                        release_month: 3, release_day: 15,
                        platforms: [ "PlayStation 5" ])
      create(:game_genre,     game: g, genre: genre)
      create(:game_developer, game: g, company: dev_co)
      create(:game_publisher, game: g, company: pub_co)
      g.reload
    end

    let(:games)   { ::Game.includes(:genres, :developer_companies, :publisher_companies).where(id: game.id) }
    let(:columns) { %i[developer publisher genre platform release_date year] }

    subject(:payload) { described_class.call(games, conversation: conversation, columns: columns) }

    it "has fixed_trailing == 2 (release_date + year)" do
      expect(payload["fixed_trailing"]).to eq(2)
    end

    it "columns are in canonical order (platform, genre, developer, publisher, release_date, year)" do
      # The table_heading reflects canonical order after the leading # and Game entries
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      expect(heading_texts).to eq(%w[# Game Platform Genre Developer Publisher Release Year])
    end

    it "# heading is a right-aligned hash" do
      expect(payload["table_heading"].first).to eq({ "text" => "#", "class" => "text-right" })
    end

    it "Year heading is a right-aligned hash" do
      year_entry = payload["table_heading"].find { |h| h.is_a?(Hash) && h["text"] == "Year" }
      expect(year_entry).to eq({ "text" => "Year", "class" => "text-right" })
    end

    it "Release heading is a plain left-aligned string (date phrases read left-to-right)" do
      expect(payload["table_heading"]).to include("Release")
    end

    it "Year cell is right-aligned with tabular-nums" do
      row     = payload["table_rows"].first
      # Find year cell (last cell)
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      year_idx = heading_texts.index("Year")
      year_cell = row[:cells][year_idx]
      expect(year_cell[:class]).to include("text-right")
      expect(year_cell[:class]).to include("tabular-nums")
    end

    it "Release cell is left-aligned (date phrases read left-to-right)" do
      row     = payload["table_rows"].first
      heading_texts = payload["table_heading"].map { |h| h.is_a?(Hash) ? h["text"] : h }
      release_idx = heading_texts.index("Release")
      release_cell = row[:cells][release_idx]
      expect(release_cell[:class]).not_to include("text-right")
    end
  end
end
