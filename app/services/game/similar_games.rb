# Similar-games recommendations.
#
# Returns the games most semantically similar to a given game, ranked
# by cosine distance on the embedding column behind `Game::EMBEDDING_COLUMN`
# (the seam — canonically `summary_embedding`, the 768-dim local-embedder
# column). Backs the "similar games" right shelf on the game show page.
#
# The query rides on the `neighbor` gem's `nearest_neighbors` helper
# (declared via `has_neighbors Game::EMBEDDING_COLUMN` on `Game`), which
# generates a `<column> <=> ?` ORDER BY against the pgvector HNSW index
# (`index_games_on_summary_embedding_hnsw`, `vector_cosine_ops`). The
# input game is excluded; rows without an embedding are skipped silently.
#
# Empty / unembedded input → `Game.none`. Callers can `.to_a` the
# result without nil-guarding the singular case.
class Game
  class SimilarGames
    DEFAULT_LIMIT = 10

    def self.call(game, limit: DEFAULT_LIMIT)
      new(game, limit: limit).call
    end

    def initialize(game, limit: DEFAULT_LIMIT)
      @game = game
      @limit = limit
    end

    def call
      return Game.none if @game.nil?
      return Game.none if @game.embedding_vector.blank?

      Game.where.not(id: @game.id)
          .nearest_neighbors(Game::EMBEDDING_COLUMN, @game.embedding_vector, distance: "cosine")
          .limit(@limit)
    end
  end
end
