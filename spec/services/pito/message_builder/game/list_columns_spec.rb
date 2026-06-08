# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::MessageBuilder::Game::ListColumns do
  # ── vocabulary ──────────────────────────────────────────────────────────────

  describe ".vocabulary" do
    subject(:vocab) { described_class.vocabulary }

    it "returns a Hash" do
      expect(vocab).to be_a(Hash)
    end

    it "maps 'platform' to :platform" do
      expect(vocab["platform"]).to eq(:platform)
    end

    it "maps 'platforms' to :platform" do
      expect(vocab["platforms"]).to eq(:platform)
    end

    it "maps 'genre' to :genre" do
      expect(vocab["genre"]).to eq(:genre)
    end

    it "maps 'genres' to :genre" do
      expect(vocab["genres"]).to eq(:genre)
    end

    it "maps 'developer' to :developer" do
      expect(vocab["developer"]).to eq(:developer)
    end

    it "maps 'dev' to :developer" do
      expect(vocab["dev"]).to eq(:developer)
    end

    it "maps 'publisher' to :publisher" do
      expect(vocab["publisher"]).to eq(:publisher)
    end

    it "maps 'release date' to :release_date" do
      expect(vocab["release date"]).to eq(:release_date)
    end

    it "maps 'year' to :year" do
      expect(vocab["year"]).to eq(:year)
    end

    it "does not include unknown tokens" do
      expect(vocab.key?("unknown_token")).to be(false)
    end
  end

  # ── headings ────────────────────────────────────────────────────────────────

  describe ".headings" do
    it "returns an empty array for no columns" do
      expect(described_class.headings([])).to eq([])
    end

    it "returns the heading for a single column" do
      expect(described_class.headings([ :genre ])).to eq([ "Genre" ])
    end

    it "returns headings in the requested order" do
      expect(described_class.headings([ :year, :developer ])).to eq([ "Year", "Developer" ])
    end

    it "includes all six headings when all columns are requested" do
      all = %i[platform genre developer publisher release_date year]
      expect(described_class.headings(all)).to eq(
        [ "Platform", "Genre", "Developer", "Publisher", "Release", "Year" ]
      )
    end
  end

  # ── cells ────────────────────────────────────────────────────────────────────

  describe ".cells" do
    let(:action_genre)  { create(:genre, name: "Action") }
    let(:rpg_genre)     { create(:genre, name: "Role-playing") }
    let(:dev_company)   { create(:company, name: "From Software") }
    let(:pub_company)   { create(:company, name: "Bandai Namco") }

    let(:game) do
      g = create(:game, title: "Elden Ring", release_year: 2022,
                         release_month: 2, release_day: 25,
                         platforms: [ "PlayStation 5", "PC (Microsoft Windows)" ])
      create(:game_genre,    game: g, genre: action_genre)
      create(:game_genre,    game: g, genre: rpg_genre)
      create(:game_developer, game: g, company: dev_company)
      create(:game_publisher, game: g, company: pub_company)
      g.reload
    end

    it "returns an empty array for no columns" do
      expect(described_class.cells(game, [])).to eq([])
    end

    it "returns cells with text-fg-dim class" do
      result = described_class.cells(game, [ :genre ])
      expect(result.first[:class]).to eq("text-fg-dim")
    end

    it "returns genre names joined by ', '" do
      result = described_class.cells(game, [ :genre ])
      expect(result.first[:text]).to include("Action")
      expect(result.first[:text]).to include("Role-playing")
    end

    it "returns developer company names" do
      result = described_class.cells(game, [ :developer ])
      expect(result.first[:text]).to include("From Software")
    end

    it "returns publisher company names" do
      result = described_class.cells(game, [ :publisher ])
      expect(result.first[:text]).to include("Bandai Namco")
    end

    it "returns platform strings joined by ', '" do
      result = described_class.cells(game, [ :platform ])
      expect(result.first[:text]).to include("PlayStation 5")
      expect(result.first[:text]).to include("PC (Microsoft Windows)")
    end

    it "returns the release year as a string" do
      result = described_class.cells(game, [ :year ])
      expect(result.first[:text]).to eq("2022")
    end

    it "returns '—' for a game with no release year" do
      tba_game = create(:game, :tba)
      result   = described_class.cells(tba_game, [ :year ])
      expect(result.first[:text]).to eq("—")
    end

    it "returns the release label for :release_date" do
      result = described_class.cells(game, [ :release_date ])
      expect(result.first[:text]).to be_a(String)
      expect(result.first[:text]).not_to be_empty
    end

    it "returns cells in the requested column order" do
      result = described_class.cells(game, [ :year, :developer ])
      expect(result.size).to eq(2)
      expect(result[0][:text]).to eq("2022")
      expect(result[1][:text]).to include("From Software")
    end
  end
end
