# frozen_string_literal: true

module Pito
  module Recommendation
    # game → game similarity — the primitive the channel directions compose.
    #
    # Blends five signals into one 0–100 score (see Weights): embedding (E),
    # genre (G), developer (D), publisher (P), and score-proximity (S). Returns
    # `Result`s ranked best-first, each carrying a `breakdown` so the score is
    # explainable. Drops anything below Weights::FLOOR.
    #
    # Candidate pool = the embedding-nearest games UNION games sharing at least
    # one genre / developer / publisher with the target. The union matters: a
    # same-developer game that sits far in embedding space still surfaces on D,
    # and a never-embedded game still scores on its facets. (At scale the pool
    # would move into SQL; here it stays a bounded in-memory blend so every
    # signal is trivially testable.)
    class GameSimilarity
      DEFAULT_LIMIT  = 10
      CANDIDATE_POOL = 50 # embedding-nearest games pulled before facet union

      Result = Struct.new(:game, :score, :breakdown, keyword_init: true)

      def self.call(game, limit: DEFAULT_LIMIT)
        new(game, limit: limit).call
      end

      def initialize(game, limit: DEFAULT_LIMIT)
        @game  = game
        @limit = limit
      end

      def call
        return [] if @game.nil?

        candidates = candidate_games
        return [] if candidates.empty?

        distances     = embedding_distances(candidates.map(&:id))
        target_genres = facet_ids(@game, :genres)
        target_devs   = facet_ids(@game, :developer_companies)
        target_pubs   = facet_ids(@game, :publisher_companies)

        candidates.filter_map { |cand|
          breakdown = {
            e: Signals.embedding(distances[cand.id]),
            g: Signals.jaccard(target_genres, facet_ids(cand, :genres)),
            d: Signals.jaccard(target_devs,   facet_ids(cand, :developer_companies)),
            p: Signals.jaccard(target_pubs,   facet_ids(cand, :publisher_companies)),
            s: Signals.score_proximity(@game.score, cand.score)
          }
          score = Weights.blend(breakdown)
          next if score < Weights::FLOOR

          Result.new(game: cand, score: score, breakdown: breakdown)
        }.sort_by { |r| [ -r.score, r.game.id ] }.first(@limit)
      end

      private

      def candidate_games
        ids = (embedding_pool_ids + facet_pool_ids).uniq - [ @game.id ]
        return [] if ids.empty?

        ::Game.where(id: ids)
              .includes(:genres, :developer_companies, :publisher_companies)
              .to_a
      end

      def embedding_pool_ids
        return [] if @game.summary_embedding.blank?

        ::Game.where.not(id: @game.id)
              .where.not(summary_embedding: nil)
              .nearest_neighbors(:summary_embedding, @game.summary_embedding, distance: "cosine")
              .limit(CANDIDATE_POOL)
              .pluck(:id)
      end

      # Games that share >= 1 genre, developer, or publisher with the target.
      def facet_pool_ids
        ids = []
        ids += join_pool(:game_genres, :genre_id, @game.genres.ids)
        ids += join_pool(:game_developers, :company_id, @game.developer_companies.ids)
        ids += join_pool(:game_publishers, :company_id, @game.publisher_companies.ids)
        ids.uniq
      end

      def join_pool(join, column, values)
        return [] if values.blank?

        ::Game.joins(join).where(join => { column => values }).distinct.pluck(:id)
      end

      # Cosine distance per candidate id (nil for candidates with no embedding).
      def embedding_distances(ids)
        return {} if @game.summary_embedding.blank? || ids.empty?

        ::Game.where(id: ids)
              .where.not(summary_embedding: nil)
              .nearest_neighbors(:summary_embedding, @game.summary_embedding, distance: "cosine")
              .each_with_object({}) { |row, acc| acc[row.id] = row.neighbor_distance }
      end

      # Preloaded-association ids (no extra query for candidates loaded via
      # `includes`); the target itself queries once.
      def facet_ids(game, association)
        game.public_send(association).map(&:id)
      end
    end
  end
end
