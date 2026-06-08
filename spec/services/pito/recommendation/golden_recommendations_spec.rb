# frozen_string_literal: true

require "rails_helper"
require Rails.root.join("spec/support/recommendation_fixture")

# Golden, hand-validated recommendation rankings over a FROZEN real-game corpus
# (spec/fixtures/recommendation_games.yml — exact Voyage embeddings + IGDB
# facets/themes/perspectives/scores). These scores are the CONTRACT for the
# recommendation engine: they must not change unless a weight or signal change
# is deliberately warranted (re-capture the fixture + update the numbers here in
# the same change). Every game is covered, not just one.
RSpec.describe "Golden recommendation rankings (frozen corpus)", type: :service do
  # target title => { other game title => validated similarity score }.
  # Order of equal-score ties is intentionally ignored (it depends on row id).
  expected = {
    "Pragmata" => {
      "Scars Above" => 83, "Dead Space" => 81, "Elden Ring" => 67,
      "Mad Max" => 65, "Ghosts 'n Goblins Resurrection" => 28, "Super Meat Boy" => 6
    },
    "Dead Space" => {
      "Scars Above" => 83, "Pragmata" => 81, "Mad Max" => 66,
      "Elden Ring" => 65, "Ghosts 'n Goblins Resurrection" => 21, "Super Meat Boy" => 7
    },
    "Scars Above" => {
      "Pragmata" => 83, "Dead Space" => 83, "Elden Ring" => 65,
      "Mad Max" => 65, "Ghosts 'n Goblins Resurrection" => 22, "Super Meat Boy" => 8
    },
    "Mad Max" => {
      "Dead Space" => 66, "Pragmata" => 65, "Elden Ring" => 65,
      "Scars Above" => 65, "Ghosts 'n Goblins Resurrection" => 19, "Super Meat Boy" => 6
    },
    "Elden Ring" => {
      "Pragmata" => 67, "Dead Space" => 65, "Mad Max" => 65,
      "Scars Above" => 65, "Ghosts 'n Goblins Resurrection" => 22, "Super Meat Boy" => 6
    },
    "Ghosts 'n Goblins Resurrection" => {
      "Pragmata" => 28, "Elden Ring" => 22, "Scars Above" => 22,
      "Dead Space" => 21, "Mad Max" => 19, "Super Meat Boy" => 13
    },
    "Super Meat Boy" => {
      "Ghosts 'n Goblins Resurrection" => 13, "Scars Above" => 8, "Dead Space" => 7,
      "Pragmata" => 6, "Mad Max" => 6, "Elden Ring" => 6
    }
  }

  let(:games) { RecommendationFixture.load!.index_by(&:title) }

  it "loads the full frozen corpus (7 games)" do
    expect(games.size).to eq(7)
  end

  expected.each do |title, expected_scores|
    it "ranks similar games for #{title.inspect} with the validated scores" do
      target  = games.fetch(title)
      results = Pito::Recommendations.similar_games(target, limit: 10)

      # Every other game scored exactly as validated (tie order ignored).
      actual = results.to_h { |r| [ r.game.title, r.score ] }
      expect(actual).to eq(expected_scores)

      # …and returned best-first.
      scores = results.map(&:score)
      expect(scores).to eq(scores.sort.reverse)
    end
  end
end
