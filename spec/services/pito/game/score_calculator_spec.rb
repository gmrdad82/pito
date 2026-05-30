# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Game::ScoreCalculator do
  describe ".call" do
    it "returns 0 for a nil game" do
      expect(described_class.call(nil)).to eq(0)
    end

    it "returns 0 when no rating contributions exist" do
      game = create(:game)
      expect(described_class.call(game)).to eq(0)
    end

    it "returns the vote-weighted average rounded to an integer" do
      game = create(:game,
                    igdb_rating: 85.0,       igdb_rating_count: 100,
                    aggregated_rating: 75.0, aggregated_rating_count: 50,
                    total_rating: 80.0,      total_rating_count: 75)

      # (85*100 + 75*50 + 80*75) / (100 + 50 + 75)
      # = (8500 + 3750 + 6000) / 225 = 18250 / 225 = 81.11... → 81
      expect(described_class.call(game)).to eq(81)
    end

    it "returns the single triplet's rating when only one has votes" do
      game = create(:game,
                    igdb_rating: 90.0, igdb_rating_count: 50)
      expect(described_class.call(game)).to eq(90)
    end

    it "ignores triplets where count is zero" do
      game = create(:game,
                    igdb_rating: 80.0,       igdb_rating_count: 0,
                    aggregated_rating: 70.0, aggregated_rating_count: 0,
                    total_rating: 90.0,      total_rating_count: 100)
      expect(described_class.call(game)).to eq(90)
    end

    it "ignores triplets where rating is nil" do
      game = create(:game,
                    igdb_rating: nil, igdb_rating_count: 100,
                    total_rating: 80.0, total_rating_count: 50)
      expect(described_class.call(game)).to eq(80)
    end

    # ── Extreme / edge-case scores ──────────────────────────────

    it "returns 100 when all ratings are maxed" do
      game = create(:game,
                    igdb_rating: 100.0,       igdb_rating_count: 200,
                    aggregated_rating: 100.0, aggregated_rating_count: 100,
                    total_rating: 100.0,      total_rating_count: 300)
      expect(described_class.call(game)).to eq(100)
    end

    it "returns 0 when all ratings are zero with votes" do
      game = create(:game,
                    igdb_rating: 0.0,       igdb_rating_count: 50,
                    aggregated_rating: 0.0,  aggregated_rating_count: 50,
                    total_rating: 0.0,       total_rating_count: 50)
      expect(described_class.call(game)).to eq(0)
    end

    it "returns 1 for a minimal nonzero score" do
      game = create(:game,
                    igdb_rating: 1.0, igdb_rating_count: 1)
      expect(described_class.call(game)).to eq(1)
    end

    it "handles a high-vote-count triplet correctly" do
      game = create(:game,
                    igdb_rating: 75.0, igdb_rating_count: 1_000_000)
      expect(described_class.call(game)).to eq(75)
    end

    it "weights the average by vote count correctly (extreme disparity)" do
      game = create(:game,
                    igdb_rating: 100.0,      igdb_rating_count: 1,
                    aggregated_rating: 50.0, aggregated_rating_count: 9999)
      # (100*1 + 50*9999) / (1 + 9999) = (100 + 499950) / 10000 = 500050 / 10000 = 50.005 → 50
      expect(described_class.call(game)).to eq(50)
    end
  end
end
