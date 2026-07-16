# frozen_string_literal: true

module Pito
  module Recommendation
    # game → game similarity — the STATIC intrinsic kernel the channel
    # directions compose over. (v2)
    #
    # Blends the v2 signal set (see Weights) — embedding · genre · theme ·
    # perspective · score-smile · TTB-smile · era · platform · developer ·
    # publisher — but only over the signals actually PRESENT for the pair
    # (`breakdown_for`): a facet missing on both games is omitted, not scored 0,
    # and `Weights.blend` normalizes by the present-weight sum. Returns `Result`s
    # ranked best-first with an explainable `breakdown`; drops below Weights::FLOOR.
    #
    # Candidate pool = the embedding-nearest games UNION games sharing at least
    # one genre / developer / publisher with the target. The union matters: a
    # same-developer game far in embedding space still surfaces on D, and a
    # never-embedded game still scores on its facets. (At scale the pool would
    # move into SQL; here it stays a bounded in-memory blend so every signal is
    # trivially testable.)
    class GameSimilarity
      DEFAULT_LIMIT  = 10
      CANDIDATE_POOL = 50 # embedding-nearest games pulled before facet union

      Result = Struct.new(:game, :score, :breakdown, keyword_init: true)

      def self.call(game, limit: DEFAULT_LIMIT)
        new(game, limit: limit).call
      end

      # Pairwise blended similarity between two SPECIFIC games — no candidate
      # pool, no floor. This is what the channel directions compose. Returns
      # { score: 0–100, breakdown: { present signals only } }. `between(g, g)`
      # is 100 only when g carries facets/embedding; identity is not assumed, so
      # callers needing a definitive self-match use LINK_SCORE.
      def self.between(game_a, game_b)
        breakdown = breakdown_for(
          facets_of(game_a), facets_of(game_b),
          cosine_distance(game_a&.embedding_vector, game_b&.embedding_vector)
        )
        { score: Weights.blend(breakdown), breakdown: breakdown }
      end

      # Snapshot of a game's facet values (ids for associations, raw for the
      # scalars). nil game → empty snapshot (everything absent).
      def self.facets_of(game)
        return {} if game.nil?

        {
          genres:       facet(game, :genres),
          themes:       Array(game.themes),
          perspectives: Array(game.player_perspectives),
          devs:         facet(game, :developer_companies),
          pubs:         facet(game, :publisher_companies),
          platforms:    Array(game.platforms),
          score:        game.score,
          ttb:          game.ttb_main_seconds,
          year:         game.release_year
        }
      end

      # Build a breakdown containing ONLY the signals present for the pair: a
      # jaccard facet is present when EITHER game has it (an empty-vs-something
      # match is a real 0); score/ttb/era/embedding need BOTH sides. Absent
      # signals are omitted so `Weights.blend` normalizes over what's comparable.
      def self.breakdown_for(facets_a, facets_b, embedding_distance)
        bd = {}
        bd[:e]  = Signals.embedding(embedding_distance) unless embedding_distance.nil?
        bd[:g]  = Signals.jaccard(facets_a[:genres], facets_b[:genres])             if union?(facets_a[:genres], facets_b[:genres])
        bd[:t]  = Signals.jaccard(facets_a[:themes], facets_b[:themes])             if union?(facets_a[:themes], facets_b[:themes])
        bd[:pp] = Signals.jaccard(facets_a[:perspectives], facets_b[:perspectives]) if union?(facets_a[:perspectives], facets_b[:perspectives])
        bd[:d]  = Signals.jaccard(facets_a[:devs], facets_b[:devs])                 if union?(facets_a[:devs], facets_b[:devs])
        bd[:p]  = Signals.jaccard(facets_a[:pubs], facets_b[:pubs])                 if union?(facets_a[:pubs], facets_b[:pubs])
        bd[:platform] = Signals.platform_overlap(facets_a[:platforms], facets_b[:platforms]) if union?(facets_a[:platforms], facets_b[:platforms])
        bd[:s]  = Signals.score_smile(facets_a[:score], facets_b[:score])  if facets_a[:score] && facets_b[:score]
        bd[:ttb] = Signals.ttb_smile(facets_a[:ttb], facets_b[:ttb])       if facets_a[:ttb] && facets_b[:ttb]
        bd[:era] = Signals.era(facets_a[:year], facets_b[:year])           if facets_a[:year] && facets_b[:year]
        bd
      end

      def self.union?(a, b)
        (Array(a) + Array(b)).any?
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

        distances     = embedding_distances(candidates)
        target_facets = self.class.facets_of(@game)

        candidates.filter_map { |cand|
          breakdown = self.class.breakdown_for(target_facets, self.class.facets_of(cand), distances[cand.id])
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
        return [] if @game.embedding_vector.blank?

        ::Game.where.not(id: @game.id)
              .where.not(::Game::EMBEDDING_COLUMN => nil)
              .nearest_neighbors(::Game::EMBEDDING_COLUMN, @game.embedding_vector, distance: "cosine")
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
      # Computed EXACTLY in Ruby (same path as `.between`) over the already-loaded
      # candidates — NOT via the approximate HNSW `nearest_neighbors`. HNSW stays
      # in `embedding_pool_ids` for pool *selection* (approximation is fine there),
      # but scoring must be exact and deterministic: an approximate distance miss
      # would drop the `e` signal from a candidate's breakdown and flip its score.
      def embedding_distances(candidates)
        return {} if @game.embedding_vector.blank?

        candidates.each_with_object({}) do |cand, acc|
          dist = self.class.cosine_distance(@game.embedding_vector, cand.embedding_vector)
          acc[cand.id] = dist unless dist.nil?
        end
      end
    end
  end
end
