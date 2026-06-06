# frozen_string_literal: true

require "rails_helper"

RSpec.describe Genre, type: :model do
  subject(:genre) { build(:genre) }

  # ── Associations ─────────────────────────────────────────────────
  describe "associations" do
    it { is_expected.to have_many(:game_genres).dependent(:destroy) }
    it { is_expected.to have_many(:games).through(:game_genres) }
  end

  # ── Validations ──────────────────────────────────────────────────
  describe "validations" do
    it { is_expected.to validate_presence_of(:igdb_id) }
    it { is_expected.to validate_presence_of(:name) }

    it "requires uniqueness of igdb_id" do
      create(:genre, igdb_id: 9_999)
      dup = build(:genre, igdb_id: 9_999)
      expect(dup).not_to be_valid
      expect(dup.errors[:igdb_id]).to be_present
    end

    it "rejects non-integer igdb_id" do
      genre.igdb_id = 1.5
      expect(genre).not_to be_valid
    end

    it "rejects igdb_id of zero" do
      genre.igdb_id = 0
      expect(genre).not_to be_valid
    end

    it "rejects negative igdb_id" do
      genre.igdb_id = -1
      expect(genre).not_to be_valid
    end

    it "accepts a valid positive integer igdb_id" do
      genre.igdb_id = 100
      expect(genre).to be_valid
    end
  end

  # ── Dependent destroy ────────────────────────────────────────────
  describe "dependent destroy" do
    it "destroys game_genres when genre is destroyed" do
      genre = create(:genre)
      game  = create(:game)
      GameGenre.create!(game: game, genre: genre)

      expect { genre.destroy! }.to change(GameGenre, :count).by(-1)
    end
  end
end
