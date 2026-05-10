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
end
