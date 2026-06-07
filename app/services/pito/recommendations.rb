# frozen_string_literal: true

module Pito
  # Thin facade over the three recommendation services — one entry point,
  # three named directions:
  #
  #   Pito::Recommendations.similar_games(game, limit:, filters:)  → Array<Result>
  #   Pito::Recommendations.channels_for(game, limit:)             → Array<Game::ChannelRecommendation::Result>
  #   Pito::Recommendations.games_for(channel, limit:)             → Array<Channel::GameRecommendation::Result>
  #
  # The `.call` method is kept as a dummy for the import step-5 progress gate
  # in `GameImportJob` — it returns `true` unconditionally and must never be
  # changed to do real work (P11 depends on it staying cheap and infallible).
  #
  # ## similar_games filter layer
  #
  # `SimilarGames` fetches a larger candidate pool (CANDIDATE_MULTIPLIER × limit,
  # floored at MIN_CANDIDATE_POOL) so the filter layer has room to prune. Each
  # candidate game is then tested against every active filter key:
  #
  #   :genre      — game shares at least one genre slug with the filter value
  #                 (String slug or Array of slugs)
  #   :year       — game.release_year equals the Integer filter value
  #   :developer  — game shares at least one developer company name (case-insensitive)
  #   :publisher  — game shares at least one publisher company name (case-insensitive)
  #   :platform   — game.platforms (text[]) includes the filter string (case-insensitive)
  #   :score      — game.score >= Integer filter value (minimum score floor)
  #   :ttb        — TTB bucket match: maps filter string ("short"/"medium"/"long") to
  #                 a range of ttb_main_seconds and keeps games whose main-hours fall
  #                 in that bucket (short: <5h, medium: 5–20h, long: >20h)
  #   :complexity — alias for :ttb (same bucket logic)
  #
  # After filtering, candidates are converted to Result structs. The distance
  # comes from `neighbor_distance` (pgvector HNSW), converted to a 0–100 score
  # via `((1 - distance) * 100).round.clamp(0, 100)` — identical to the
  # ChannelRecommendation convention so all three directions are comparable.
  # TopK selects the final limit from the filtered list.
  module Recommendations
    module_function

    # ---------- public API --------------------------------------------------

    # Dummy step-5 probe used by GameImportJob.
    # Returns true unconditionally so the job can broadcast "Recommendations
    # ready." without actually computing anything. Real logic lives in the
    # named methods below. DO NOT add side-effects here.
    def call(*) = true

    # Games most similar to `game` (game↔game direction).
    #
    # @param game   [::Game]
    # @param limit  [Integer] maximum results (default 10)
    # @param filters [Hash] optional filter keys (see module doc above)
    # @return [Array<Result>] best-first, each carrying game + score + distance
    def similar_games(game, limit: ::Game::SimilarGames::DEFAULT_LIMIT, filters: {})
      return [] if game.nil?
      return [] if game.summary_embedding.blank?

      pool_size = [ limit * CANDIDATE_MULTIPLIER, MIN_CANDIDATE_POOL ].max
      candidates = ::Game::SimilarGames.call(game, limit: pool_size).to_a

      filtered = filters.empty? ? candidates : apply_filters(candidates, filters)

      scored = filtered.map { |g| build_result(g) }
      Pito::Recommendation::TopK.call(items: scored.map(&:to_h), k: limit)
        .filter_map { |h| scored.find { |r| r.game.id == h[:id] } }
    end

    # Channels whose videos overlap with `game` (game→channel direction).
    #
    # @param game  [::Game]
    # @param limit [Integer] maximum results (default from service)
    # @return [Array<Game::ChannelRecommendation::Result>]
    def channels_for(game, limit: ::Game::ChannelRecommendation::DEFAULT_LIMIT)
      ::Game::ChannelRecommendation.call(game, limit: limit)
    end

    # Games that a channel's top videos overlap with (channel→game direction).
    #
    # @param channel [::Channel]
    # @param limit   [Integer] maximum results (default from service)
    # @return [Array<Channel::GameRecommendation::Result>]
    def games_for(channel, limit: ::Channel::GameRecommendation::DEFAULT_LIMIT)
      ::Channel::GameRecommendation.call(channel, limit: limit)
    end

    # ---------- Result struct -----------------------------------------------

    # Carries a game record, a 0–100 score, and the raw cosine distance so
    # renderers (e.g. ScoreBarComponent) receive all three fields consistently
    # with Game::ChannelRecommendation::Result and Channel::GameRecommendation::Result.
    Result = Struct.new(:game, :score, :distance, keyword_init: true) do
      def to_h
        { id: game.id, score: score }
      end
    end

    # ---------- private helpers ---------------------------------------------

    # How many candidates to fetch from SimilarGames before applying filters.
    CANDIDATE_MULTIPLIER = 5
    MIN_CANDIDATE_POOL   = 50

    # TTB bucket definitions (ttb_main_seconds).
    TTB_BUCKETS = {
      "short"  => (0...(5 * 3600)),
      "medium" => ((5 * 3600)...(20 * 3600)),
      "long"   => ((20 * 3600)..Float::INFINITY)
    }.freeze

    private_constant :CANDIDATE_MULTIPLIER, :MIN_CANDIDATE_POOL, :TTB_BUCKETS

    def build_result(game)
      distance = game.neighbor_distance.to_f
      score    = ((1 - distance) * 100).round.clamp(0, 100)
      Result.new(game: game, score: score, distance: distance)
    end

    def apply_filters(candidates, filters)
      candidates.select { |g| passes_all?(g, filters) }
    end

    def passes_all?(game, filters)
      filters.all? { |key, value| passes_filter?(game, key.to_sym, value) }
    end

    # rubocop:disable Metrics/MethodLength, Metrics/CyclomaticComplexity
    def passes_filter?(game, key, value)
      case key
      when :genre
        genre_slugs = Array(value).map(&:to_s)
        game.genres.map(&:slug).any? { |s| genre_slugs.include?(s) }
      when :year
        game.release_year == value.to_i
      when :developer
        names = Array(value).map { |n| n.to_s.downcase }
        game.developer_companies.map { |c| c.name.downcase }.any? { |n| names.include?(n) }
      when :publisher
        names = Array(value).map { |n| n.to_s.downcase }
        game.publisher_companies.map { |c| c.name.downcase }.any? { |n| names.include?(n) }
      when :platform
        needle = value.to_s.downcase
        Array(game.platforms).any? { |p| p.to_s.downcase == needle }
      when :score
        game.score.present? && game.score >= value.to_i
      when :ttb, :complexity
        bucket = TTB_BUCKETS[value.to_s]
        return true if bucket.nil? # unknown bucket name → pass-through

        game.ttb_main_seconds.present? && bucket.cover?(game.ttb_main_seconds)
      else
        true # unknown filter keys are ignored (future-proof)
      end
    end
    # rubocop:enable Metrics/MethodLength, Metrics/CyclomaticComplexity
  end
end
