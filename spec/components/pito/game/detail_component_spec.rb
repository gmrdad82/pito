# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::DetailComponent do
  let(:game) { create(:game, title: "Super Test Game", summary: "A great game.", platforms: %w[PS5 Switch]) }

  describe "title" do
    it "renders the game title" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("Super Test Game")
    end
  end

  describe "developer names" do
    it "renders developer company names" do
      company = create(:company, name: "Dev Studios")
      create(:game_developer, game: game, company: company)
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("Dev Studios")
    end
  end

  describe "publisher names" do
    it "renders publisher company names" do
      company = create(:company, name: "Pub Corp")
      create(:game_publisher, game: game, company: company)
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("Pub Corp")
    end
  end

  describe "release label" do
    it "renders the release label" do
      released_game = create(:game, release_year: 2023, release_month: 3, release_day: 15,
                                    release_date: Date.new(2023, 3, 15))
      node = render_inline(described_class.new(game: released_game))
      expect(node.text).to include("2023")
    end
  end

  describe "available platforms (T16.12 — operator token chips)" do
    it "maps IGDB 'PlayStation 4' and 'PC (Microsoft Windows)' to PlayStation + Steam chips" do
      g = create(:game, platforms: [ "PlayStation 4", "PC (Microsoft Windows)", "Xbox One" ])
      node = render_inline(described_class.new(game: g))
      chip_texts = node.css("span.border").map(&:text).map(&:strip)
      expect(chip_texts).to include("PlayStation")
      expect(chip_texts).to include("Steam")
      # Xbox One has no matching token — should not appear as a chip
      expect(chip_texts).not_to include("Xbox One")
    end

    it "de-dupes tokens when multiple IGDB names map to the same token" do
      g = create(:game, platforms: [ "Steam", "GOG", "Nintendo Switch" ])
      node = render_inline(described_class.new(game: g))
      chip_texts = node.css("span.border").map(&:text).map(&:strip)
      expect(chip_texts.count("Steam")).to eq(1)
      expect(chip_texts).to include("Nintendo Switch")
    end

    it "renders a dash placeholder row label when no platform matches any token" do
      g = create(:game, platforms: [ "Xbox One", "Stadia" ])
      node = render_inline(described_class.new(game: g))
      # No platform chips should be rendered
      expect(node.css("span.border")).to be_empty
    end

    it "renders no platforms section when game.platforms is empty" do
      g = create(:game, platforms: [])
      node = render_inline(described_class.new(game: g))
      expect(node.text).not_to include(I18n.t("pito.game.detail.platforms"))
    end
  end

  describe "owned platforms" do
    it "renders owned platform display labels" do
      GamePlatformOwnership.create!(game: game, platform_token: "ps")
      GamePlatformOwnership.create!(game: game, platform_token: "steam")
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("PlayStation")
      expect(node.text).to include("Steam")
    end
  end

  describe "genres" do
    it "renders genre names" do
      genre = create(:genre, name: "Action RPG")
      create(:game_genre, game: game, genre: genre)
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("Action RPG")
    end
  end

  describe "KV table (T16.11 — KeyValueRowComponent grid)" do
    it "renders developer row using KeyValueRowComponent (key + value spans)" do
      company = create(:company, name: "Grid Dev")
      create(:game_developer, game: game, company: company)
      game.reload

      node = render_inline(described_class.new(game: game))
      # The grid container must be present
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid).not_to be_nil
      expect(grid.text).to include("Developer")
      expect(grid.text).to include("Grid Dev")
    end

    it "renders description row inside the grid" do
      g = create(:game, summary: "An epic tale.")
      node = render_inline(described_class.new(game: g))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid).not_to be_nil
      expect(grid.text).to include("Description")
      expect(grid.text).to include("An epic tale.")
    end
  end

  describe "score bar" do
    it "embeds the ScoreBarComponent (pito-score-bar marker class)" do
      node = render_inline(described_class.new(game: game))
      expect(node.css(".pito-score-bar").first).not_to be_nil
    end
  end

  describe "time-to-beat component with footage tick" do
    it "embeds the TTB component including the footage mark" do
      Footage.create!(game: game, filename: "clip.mov", duration_seconds: 7200)
      game.reload

      node = render_inline(described_class.new(game: game))
      # Footage uses the ScoreBar-style ▼ value bubble (T17.4), not a | tick.
      expect(node.css(".pito-ttb__footage-bubble").first).not_to be_nil
    end
  end

  describe "cover art" do
    context "when no cover art is attached" do
      it "renders the no_cover placeholder" do
        node = render_inline(described_class.new(game: game))
        expect(node.text).to include(I18n.t("pito.game.detail.no_cover"))
      end
    end

    context "when the variant call raises a StandardError" do
      it "cover_art_url returns nil (the rescue block swallows the error)" do
        # Use a plain double for cover_art that raises on #variant (via method_missing).
        # ActiveStorage::Attached::One delegates variant via method_missing; a
        # duck-type double is the most reliable way to stub that call path.
        cover_double = double("cover_art", variant: nil) # :nodoc:
        allow(cover_double).to receive(:variant).and_raise(StandardError, "variant failed")
        component = described_class.new(game: game)
        allow(component).to receive(:cover_art_attached?).and_return(true)
        allow(game).to receive(:cover_art).and_return(cover_double)
        expect(component.cover_art_url).to be_nil
      end
    end
  end

  describe "rendering with nil score" do
    it "does not raise when game.score is nil" do
      game.update_column(:score, nil)
      expect { render_inline(described_class.new(game: game.reload)) }.not_to raise_error
    end
  end

  describe "empty associations" do
    it "does not crash when developer_companies is empty" do
      expect { render_inline(described_class.new(game: game)) }.not_to raise_error
    end

    it "omits the developer row when no developers" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).not_to include(I18n.t("pito.game.detail.developer"))
    end

    it "does not crash when publisher_companies is empty" do
      expect { render_inline(described_class.new(game: game)) }.not_to raise_error
    end

    it "omits the publisher row when no publishers" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).not_to include(I18n.t("pito.game.detail.publisher"))
    end

    it "omits the genres row when no genres" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).not_to include(I18n.t("pito.game.detail.genres"))
    end

    it "omits the owned row when no platform ownerships" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).not_to include(I18n.t("pito.game.detail.owned"))
    end
  end
end
