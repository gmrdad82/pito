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
      "Scars Above" => 70, "Dead Space" => 67, "Ghosts 'n Goblins Resurrection" => 36,
      "Elden Ring" => 46, "Mad Max" => 43
    },
    "Dead Space" => {
      "Scars Above" => 72, "Pragmata" => 67, "Mad Max" => 46,
      "Elden Ring" => 43, "Ghosts 'n Goblins Resurrection" => 22
    },
    "Scars Above" => {
      "Dead Space" => 72, "Pragmata" => 70, "Elden Ring" => 43,
      "Mad Max" => 43, "Ghosts 'n Goblins Resurrection" => 23
    },
    "Mad Max" => {
      "Dead Space" => 46, "Elden Ring" => 47, "Ghosts 'n Goblins Resurrection" => 21,
      "Pragmata" => 43, "Scars Above" => 43
    },
    "Elden Ring" => {
      "Mad Max" => 47, "Pragmata" => 46, "Dead Space" => 43,
      "Scars Above" => 43, "Ghosts 'n Goblins Resurrection" => 22
    },
    "Ghosts 'n Goblins Resurrection" => {
      "Pragmata" => 36, "Elden Ring" => 22, "Scars Above" => 23,
      "Dead Space" => 22, "Mad Max" => 21, "Super Meat Boy" => 13
    },
    "Super Meat Boy" => {
      "Ghosts 'n Goblins Resurrection" => 13
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
