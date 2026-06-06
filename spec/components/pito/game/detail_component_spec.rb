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

  describe "available platforms" do
    it "renders the available platforms from game.platforms" do
      node = render_inline(described_class.new(game: game))
      expect(node.text).to include("PS5")
      expect(node.text).to include("Switch")
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

  describe "score bar" do
    it "embeds the ScoreBarComponent (pito-score-bar marker class)" do
      node = render_inline(described_class.new(game: game))
      expect(node.css(".pito-score-bar").first).not_to be_nil
    end
  end

  describe "time-to-beat component with footage tick" do
    it "embeds the TTB component including the footage tick" do
      Footage.create!(game: game, filename: "clip.mov", duration_seconds: 7200)
      game.reload

      node = render_inline(described_class.new(game: game))
      expect(node.css(".ttb-tick--footage").first).not_to be_nil
    end
  end

  describe "cover art" do
    context "when no cover art is attached" do
      it "renders the no_cover placeholder" do
        node = render_inline(described_class.new(game: game))
        expect(node.text).to include(I18n.t("pito.game.detail.no_cover"))
      end
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
