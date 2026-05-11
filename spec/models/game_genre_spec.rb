require "rails_helper"

RSpec.describe GameGenre, type: :model do
  describe "associations" do
    it { is_expected.to belong_to(:game) }
    it { is_expected.to belong_to(:genre) }
  end

  describe "uniqueness" do
    it "is unique on (game_id, genre_id)" do
      g = create(:game)
      genre = create(:genre)
      create(:game_genre, game: g, genre: genre)
      dup = build(:game_genre, game: g, genre: genre)
      expect(dup).not_to be_valid
    end
  end

  describe "cascade" do
    it "is destroyed when its game is destroyed" do
      gg = create(:game_genre)
      expect { gg.game.destroy! }.to change { GameGenre.count }.by(-1)
    end

    it "is destroyed when its genre is destroyed" do
      gg = create(:game_genre)
      expect { gg.genre.destroy! }.to change { GameGenre.count }.by(-1)
    end
  end

  # Phase 27 follow-up (2026-05-11) — `games.primary_genre_id` upkeep.
  describe "primary_genre upkeep" do
    it "sets game.primary_genre_id on first join when blank" do
      game  = create(:game, title: "Fresh")
      genre = create(:genre, name: "Adventure", igdb_id: 7_001)
      game.update_column(:primary_genre_id, nil)

      expect { game.genres << genre }
        .to change { game.reload.primary_genre_id }.from(nil).to(genre.id)
    end

    it "does NOT clobber an existing pin when adding additional genres" do
      adventure = create(:genre, name: "Adventure", igdb_id: 7_011)
      rpg       = create(:genre, name: "RPG",       igdb_id: 7_012)
      shooter   = create(:genre, name: "Shooter",   igdb_id: 7_013)
      game      = create(:game, title: "Pinned game")
      game.genres << shooter  # picker pins shooter (only option)

      # Now add adventure + rpg. The pin should stay on shooter.
      game.genres << [ adventure, rpg ]
      expect(game.reload.primary_genre_id).to eq(shooter.id)
    end

    it "picks the alphabetical-first genre when multiple are linked from blank" do
      adventure = create(:genre, name: "Adventure", igdb_id: 7_021)
      rpg       = create(:genre, name: "RPG",       igdb_id: 7_022)
      shooter   = create(:genre, name: "Shooter",   igdb_id: 7_023)
      game      = create(:game, title: "Multi-link")
      game.update_column(:primary_genre_id, nil)
      # Link rpg first, then adventure — picker still picks adventure
      # alphabetically when the pin is cleared.
      GameGenre.create!(game: game, genre: rpg)
      game.update_column(:primary_genre_id, nil)
      GameGenre.create!(game: game, genre: adventure)
      game.update_column(:primary_genre_id, nil)
      GameGenre.create!(game: game, genre: shooter)

      expect(game.reload.primary_genre_id).to eq(adventure.id)
    end
  end
end
