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
  # `similar_games` ranks via the multi-signal blend
  # (`Pito::Recommendation::GameSimilarity`). When `filters` are given, the
  # blended results are pruned (post-filter) by every active filter key:
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
  # Results are `Pito::Recommendation::GameSimilarity::Result`s (game + 0–100
  # score + signal breakdown), already ranked best-first; filtering only removes
  # entries, it does not re-rank.
  module Recommendations
    module_function

    # ---------- public API --------------------------------------------------

    # Dummy step-5 probe used by GameImportJob.
    # Returns true unconditionally so the job can broadcast "Recommendations
    # ready." without actually computing anything. Real logic lives in the
    # named methods below. DO NOT add side-effects here.
    def call(*) = true

    # Games most similar to `game` (game↔game direction) — the multi-signal
    # blend (embedding + genre + developer + publisher + score) from
    # Pito::Recommendation::GameSimilarity. Optional `filters` prune the blended
    # results by explicit constraints (see module doc above).
    #
    # @param game   [::Game]
    # @param limit  [Integer] maximum results (default 10)
    # @param filters [Hash] optional filter keys (see module doc above)
    # @return [Array<Pito::Recommendation::GameSimilarity::Result>] best-first,
    #   each carrying game + score + breakdown.
    def similar_games(game, limit: ::Pito::Recommendation::GameSimilarity::DEFAULT_LIMIT, filters: {})
      return [] if game.nil?

      results = ::Pito::Recommendation::GameSimilarity.call(game, limit: filters.empty? ? limit : nil)
      return results if filters.empty?

      allowed = apply_filters(results.map(&:game), filters).map(&:id).to_set
      results.select { |result| allowed.include?(result.game.id) }.first(limit)
    end

    # Channels whose videos overlap with `game` (game→channel direction).
    #
    # @param game  [::Game]
    # @param limit [Integer, nil] maximum results; nil (default) returns ALL
    #   matched channels, ranked best-first.
    # @param include_all [Boolean] when true, every channel is returned (video-less
    #   ones at score 0, sorted last) — the "which channel suits this game?" surface.
    # @return [Array<Game::ChannelRecommendation::Result>]
    def channels_for(game, limit: nil, include_all: false)
      ::Game::ChannelRecommendation.call(game, limit: limit, include_all: include_all)
    end

    # Games best suited to a channel (channel→game direction).
    #
    # @param channel [::Channel]
    # @param limit   [Integer, nil] maximum results; nil (default) returns all.
    # @return [Array<Channel::GameRecommendation::Result>]
    def games_for(channel, limit: nil)
      ::Channel::GameRecommendation.call(channel, limit: limit)
    end

    # ---------- private helpers ---------------------------------------------

    # TTB bucket definitions (ttb_main_seconds).
    TTB_BUCKETS = {
      "short"  => (0...(5 * 3600)),
      "medium" => ((5 * 3600)...(20 * 3600)),
      "long"   => ((20 * 3600)..Float::INFINITY)
    }.freeze

    private_constant :TTB_BUCKETS

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
