# Phase 34 (2026-05-18) — Bundles a game should belong to.
#
# Returns the BUNDLES whose centroid sits closest (cosine distance)
# to a given game's Voyage `summary_embedding`. Backs the "bundles
# this game fits" right shelf on the game show page.
#
# Rides on the per-bundle centroid that `Bundle::VoyageIndexer`
# writes to `bundles.summary_embedding` whenever a bundle is created,
# renamed, or its membership changes (the embedding is over the
# bundle name plus the aggregated member summaries). No live centroid
# math is needed here — the column is the precomputed centroid.
#
# Bundles the game is already a member of are excluded. Bundles
# without an embedding (no name, no members, or the Voyage key was
# unconfigured at index time) are skipped silently.
#
# Empty / unembedded input → `Bundle.none`. The cosine ORDER rides on
# the `neighbor` gem's `nearest_neighbors` helper, hitting the HNSW
# index (`index_bundles_on_summary_embedding_hnsw`,
# `vector_cosine_ops`).
class Bundle
  class SuggestedFor
    DEFAULT_LIMIT = 3

    def self.call(game, limit: DEFAULT_LIMIT)
      new(game, limit: limit).call
    end

    def initialize(game, limit: DEFAULT_LIMIT)
      @game = game
      @limit = limit
    end

    def call
      return Bundle.none if @game.nil?
      return Bundle.none if @game.summary_embedding.blank?

      Bundle.where.not(id: @game.bundle_ids)
            .nearest_neighbors(:summary_embedding, @game.summary_embedding, distance: "cosine")
            .limit(@limit)
    end
  end
end
