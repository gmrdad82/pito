# Phase 34 (2026-05-18) — Bundle-membership recommender.
#
# Returns the GAMES that would semantically fit a bundle as new
# members, ranked by cosine distance from the centroid of the
# bundle's existing members' Voyage `summary_embedding` vectors.
# Backs the "you might add" shelf on the bundle show page.
#
# Centroid = component-wise arithmetic mean of the member embedding
# vectors (1024-dim). The centroid stays in memory only; we never
# persist it. Games already in the bundle and games without an
# embedding are excluded.
#
# Empty / no-embedded-members input → `Game.none`. The cosine ORDER
# rides on the `neighbor` gem's `nearest_neighbors` helper, hitting
# the HNSW index (`index_games_on_summary_embedding_hnsw`,
# `vector_cosine_ops`).
module Bundles
  class Recommender
    DEFAULT_LIMIT = 3
    EMBEDDING_DIMS = 1024

    def self.call(bundle, limit: DEFAULT_LIMIT)
      new(bundle, limit: limit).call
    end

    def initialize(bundle, limit: DEFAULT_LIMIT)
      @bundle = bundle
      @limit = limit
    end

    def call
      return Game.none if @bundle.nil?

      member_embeddings = @bundle.games
                                 .where.not(summary_embedding: nil)
                                 .pluck(:summary_embedding)
      return Game.none if member_embeddings.empty?

      centroid = average_embeddings(member_embeddings)

      Game.where.not(id: @bundle.game_ids)
          .nearest_neighbors(:summary_embedding, centroid, distance: "cosine")
          .limit(@limit)
    end

    private

    # Component-wise average. Input is an Array of Arrays (or
    # Neighbor::Vector instances — both quack via `each_with_index`).
    # Output is a plain Array<Float> of length EMBEDDING_DIMS that the
    # pgvector binding accepts directly.
    def average_embeddings(embeddings)
      sums = Array.new(EMBEDDING_DIMS, 0.0)
      embeddings.each do |vec|
        components = vec.respond_to?(:to_a) ? vec.to_a : vec
        components.each_with_index { |v, i| sums[i] += v.to_f }
      end
      sums.map { |s| s / embeddings.size }
    end
  end
end
