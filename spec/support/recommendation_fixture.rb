# frozen_string_literal: true

# Loads the frozen, hand-validated game corpus from
# spec/fixtures/recommendation_games.yml into the test DB — exact Voyage
# embeddings, IGDB scores, genres, themes, player_perspectives, developers and
# publishers. This is the golden data behind the recommendation contract specs;
# it is independent of the dev database (those games may be deleted).
module RecommendationFixture
  PATH = Rails.root.join("spec/fixtures/recommendation_games.yml")

  module_function

  # Creates the corpus and returns the Game records (by title). Idempotent only
  # within a transaction — call once per example (transactional rollback cleans
  # up) or wrap in before(:all)/after(:all) with #cleanup!.
  def load!
    data = YAML.load_file(PATH)

    genres    = lookup(data.flat_map { |r| r["genres"] }, ::Genre, 900_000)
    companies = lookup(data.flat_map { |r| r["developers"] + r["publishers"] }, ::Company, 800_000)

    data.map do |row|
      game = ::Game.create!(
        title:               row["title"],
        igdb_id:             row["igdb_id"],
        score:               row["score"],
        themes:              row["themes"],
        player_perspectives: row["player_perspectives"]
      )
      game.update_column(:summary_embedding, row["summary_embedding"])
      row["genres"].each     { |n| ::GameGenre.create!(game: game, genre: genres.fetch(n)) }
      row["developers"].each { |n| ::GameDeveloper.create!(game: game, company: companies.fetch(n)) }
      row["publishers"].each { |n| ::GamePublisher.create!(game: game, company: companies.fetch(n)) }
      game
    end
  end

  def cleanup!
    [ ::GameGenre, ::GameDeveloper, ::GamePublisher, ::Game, ::Genre, ::Company ].each(&:delete_all)
  end

  # name => record, with deterministic synthetic igdb_ids (the names are the
  # source of truth here, not IGDB ids).
  def lookup(names, klass, base)
    names.uniq.each_with_index.to_h do |name, i|
      [ name, klass.create!(igdb_id: base + i, name: name, slug: name.parameterize) ]
    end
  end
end
