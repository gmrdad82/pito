# frozen_string_literal: true

module Pito
  module Search
    # Generic pgvector semantic search — the ONE seam every domain's
    # `summary_embedding` search routes through (games, videos; later
    # conversations). Deliberately domain-agnostic: no game/video-specific
    # knowledge lives here, and no user-facing copy is rendered here — the
    # caller owns its scope/column and renders `Pito::Copy` strings from the
    # result.
    #
    # `query` is embedded via `Pito::Embedding::Client`'s forgiving `#embed`
    # contract (the wire-level task prefix is applied by the client itself —
    # this class never touches `PROMPT_PREFIX`). A nil vector (embedder
    # unconfigured, or the sidecar failed) returns nil so the CALLER can
    # render the "search unavailable" copy — this class never does.
    #
    # `scope` must be `has_neighbors <column>`-enabled (see `Game`/`Video`).
    # `nearest_neighbors` already orders ascending by distance and excludes
    # nil-embedding rows; the explicit `where.not(column => nil)` here keeps
    # that guarantee even if a caller passes a scope that hasn't already
    # filtered nils, matching this class's documented contract literally.
    class Semantic
      # Measured 2026-07-17 against the embeddinggemma-300m vector space
      # (see Pito::Embedding::Client::VECTOR_SPACE): real query/document
      # matches scored cosine similarity 0.61-0.68, unrelated noise scored
      # 0.52 — the floor sits in that gap, so noise drops and real matches
      # survive. Tunable; re-measure before moving it.
      DEFAULT_FLOOR = 0.55

      def self.call(scope:, column:, query:, limit:, floor: DEFAULT_FLOOR)
        new(scope: scope, column: column, query: query, limit: limit, floor: floor).call
      end

      def initialize(scope:, column:, query:, limit:, floor: DEFAULT_FLOOR)
        @scope  = scope
        @column = column
        @query  = query
        @limit  = limit
        @floor  = floor
      end

      def call
        vector = Pito::Embedding::Client.new.embed([ @query ]).first
        return nil if vector.nil?

        # SQL LIMIT before the floor filter — `nearest_neighbors` orders
        # ascending by distance and the floor only ever cuts a suffix of that
        # order, so bounding in SQL is semantics-preserving AND lets
        # pgvector's HNSW index serve the query instead of instantiating
        # every embedded row (768 floats each) per call.
        @scope
          .where.not(@column => nil)
          .nearest_neighbors(@column, vector, distance: "cosine")
          .limit(@limit)
          .filter_map { |record|
            similarity = 1.0 - record.neighbor_distance.to_f
            next if similarity < @floor

            { record: record, similarity: similarity }
          }
      end
    end
  end
end
