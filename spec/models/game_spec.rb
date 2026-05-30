# frozen_string_literal: true

require "rails_helper"

RSpec.describe Game, type: :model do
  describe "score auto-recomputation" do
    it "recomputes score when a rating field changes" do
      game = create(:game,
                    igdb_rating: 80.0, igdb_rating_count: 100)
      expect(game.score).to eq(80)

      game.update!(igdb_rating: 90.0)
      expect(game.score).to eq(90)
    end

    it "raises ScoreDriftError when rating changes would drift score beyond threshold" do
      game = create(:game,
                    igdb_rating: 80.0, igdb_rating_count: 100)
      expect(game.score).to eq(80)

      expect { game.update!(igdb_rating: 0.0, igdb_rating_count: 100) }
        .to raise_error(Pito::Error::ScoreDrift)
    end

    it "allows drift within threshold" do
      game = create(:game,
                    igdb_rating: 80.0, igdb_rating_count: 100)
      expect(game.score).to eq(80)

      # 80 → 55 = 25-point drift, within the 30-point threshold
      game.update!(igdb_rating: 55.0, igdb_rating_count: 100)
      expect(game.score).to eq(55)
    end

    it "does not recompute score when non-rating fields change" do
      game = create(:game,
                    title: "Original",
                    igdb_rating: 75.0, igdb_rating_count: 50)
      expect(game.score).to eq(75)

      expect { game.update!(title: "Renamed") }
        .not_to(change { game.reload.score })
    end
  end

  describe "#recompute_score!" do
    it "recomputes and persists the score, bypassing the drift guard" do
      game = create(:game,
                    igdb_rating: 90.0, igdb_rating_count: 200)
      game.update_column(:score, 0)

      expect { game.recompute_score! }
        .to change { game.reload.score }.from(0).to(90)
    end
  end
end
