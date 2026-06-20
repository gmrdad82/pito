# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::DetailComponent do
  let(:game) { create(:game, title: "Super Test Game", summary: "A great game.", platforms: %w[PS5 Switch]) }

  describe "title" do
    it "renders a Title label and the game title in the right column" do
      node  = render_inline(described_class.new(game: game))
      right = node.css(".pito-game-detail__right").first
      expect(right).not_to be_nil
      expect(right.text).to include("Title")
      expect(right.text).to include("Super Test Game")
    end

    it "puts no KV grid in the left column (cover only)" do
      node = render_inline(described_class.new(game: game))
      expect(node.css(".pito-game-detail__left div.grid")).to be_empty
    end
  end

  describe "ID row" do
    it "renders the internal db id, #-prefixed, as the first KV row before Platform" do
      node = render_inline(described_class.new(game: game))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.text).to include(I18n.t("pito.game.detail.id"))
      expect(grid.text).to include("##{game.id}")
      expect(grid.text.index(I18n.t("pito.game.detail.id")))
        .to be < grid.text.index(I18n.t("pito.game.detail.platforms"))
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

  describe "price row" do
    it "renders the Price row with the formatted euro value when the game is priced" do
      priced = create(:game, price: BigDecimal("59.99"))
      node   = render_inline(described_class.new(game: priced))
      expect(node.text).to include("Price")
      expect(node.text).to include("€59.99")
    end

    it "hides the Price row entirely when the game is unpriced" do
      node = render_inline(described_class.new(game: create(:game, price: nil)))
      expect(node.text).not_to include("€")
    end
  end

  describe "available platforms (SVG logo icons)" do
    it "renders <img> platform icons for 'PlayStation 4' and 'PC (Microsoft Windows)' (Xbox dropped)" do
      g = create(:game, platforms: [ "PlayStation 4", "PC (Microsoft Windows)", "Xbox One" ])
      node = render_inline(described_class.new(game: g))
      expect(node.css("img.pito-platform-icon").map { |i| i["src"] }).to include("/platforms/playstation.svg")
      expect(node.css("img.pito-platform-icon").map { |i| i["src"] }).to include("/platforms/steam.svg")
      # Xbox One has no matching token — no Xbox icon
      xbox_icons = node.css("img.pito-platform-icon").select { |i| i["src"].include?("xbox") }
      expect(xbox_icons).to be_empty
      # No bordered chips
      expect(node.css("span.border")).to be_empty
    end

    it "de-dupes tokens and renders icons for Switch + Steam" do
      g = create(:game, platforms: [ "Steam", "GOG", "Nintendo Switch" ])
      node = render_inline(described_class.new(game: g))
      srcs = node.css("img.pito-platform-icon").map { |i| i["src"] }
      expect(srcs.count("/platforms/steam.svg")).to eq(1)
      expect(srcs).to include("/platforms/switch.svg")
      expect(node.css("span.border")).to be_empty
    end

    it "renders no platforms row when game.platforms is empty" do
      g = create(:game, platforms: [])
      node = render_inline(described_class.new(game: g))
      expect(node.text).not_to include(I18n.t("pito.game.detail.platforms"))
    end

    it "renders icons inside the KV grid" do
      g = create(:game, platforms: [ "PlayStation 5", "Nintendo Switch" ])
      node = render_inline(described_class.new(game: g))
      grid = node.css("div.grid.grid-cols-\\[max-content_1fr\\]").first
      expect(grid.css("img.pito-platform-icon").first).not_to be_nil
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

  describe "themes + perspective" do
    it "renders the themes row when present" do
      g = create(:game, themes: [ "Horror", "Survival" ])
      node = render_inline(described_class.new(game: g))
      expect(node.text).to include("Themes")
      expect(node.text).to include("Horror, Survival")
    end

    it "renders the perspective row when present" do
      g = create(:game, player_perspectives: [ "Third person", "First person" ])
      node = render_inline(described_class.new(game: g))
      expect(node.text).to include("Perspective")
      expect(node.text).to include("Third person, First person")
    end

    it "omits both rows when empty" do
      g = create(:game, themes: [], player_perspectives: [])
      node = render_inline(described_class.new(game: g))
      expect(node.text).not_to include("Themes")
      expect(node.text).not_to include("Perspective")
    end
  end

  describe "KV table (KeyValueRowComponent grid)" do
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

    it "renders the description in the right column under a Description label" do
      g = create(:game, summary: "An epic tale.")
      node = render_inline(described_class.new(game: g))
      right = node.css(".pito-game-detail__right").first
      expect(right).not_to be_nil
      expect(right.text).to include("Description")
      expect(right.text).to include("An epic tale.")
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
      game.update!(footage_hours: 2)

      node = render_inline(described_class.new(game: game))
      # Footage uses the ScoreBar-style ▼ value bubble, not a | tick.
      bubble = node.css(".pito-ttb__footage-bubble").first
      expect(bubble).not_to be_nil
      # The bubble's value reflects the game's footage_hours via FootageHours.
      expect(bubble.text).to include("2h")
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
  end
end
