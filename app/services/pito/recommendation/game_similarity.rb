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

      # Pairwise blended similarity between two SPECIFIC games — no candidate
      # pool, no floor. This is what the channel directions compose over the
      # link graph (max similarity between a target and a channel's linked
      # games). Returns { score: 0–100, breakdown: { e:, g:, d:, p:, s: } }.
      # `between(g, g)` is 100 only when g carries facets/embedding; identity is
      # not assumed, so callers needing a definitive self-match use LINK_SCORE.
      def self.between(game_a, game_b)
        breakdown = {
          e: Signals.embedding(cosine_distance(game_a&.summary_embedding, game_b&.summary_embedding)),
          g: Signals.jaccard(facet(game_a, :genres), facet(game_b, :genres)),
          d: Signals.jaccard(facet(game_a, :developer_companies), facet(game_b, :developer_companies)),
          p: Signals.jaccard(facet(game_a, :publisher_companies), facet(game_b, :publisher_companies)),
          s: Signals.score_proximity(game_a&.score, game_b&.score)
        }
        { score: Weights.blend(breakdown), breakdown: breakdown }
      end

      def self.facet(game, association)
        return [] if game.nil?

        game.public_send(association).map(&:id)
      end

      # Cosine distance (0..2) between two embedding vectors, computed in Ruby so
      # callers can score an arbitrary pair without a per-pair pgvector query.
      # nil when either vector is absent or zero.
      def self.cosine_distance(vec_a, vec_b)
        a = coerce_vector(vec_a)
        b = coerce_vector(vec_b)
        return nil if a.nil? || b.nil? || a.size != b.size

        dot = na = nb = 0.0
        a.each_index do |i|
          dot += a[i] * b[i]
          na  += a[i]**2
          nb  += b[i]**2
        end
        return nil if na.zero? || nb.zero?

        1.0 - (dot / (Math.sqrt(na) * Math.sqrt(nb)))
      end

      def self.coerce_vector(vec)
        return nil if vec.nil?

        arr = vec.respond_to?(:to_a) ? vec.to_a : vec
        arr.empty? ? nil : arr.map(&:to_f)
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
        }.sort_by { |r| [ -r.score, r.game.id ] }.then { |ranked| @limit ? ranked.first(@limit) : ranked }
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
