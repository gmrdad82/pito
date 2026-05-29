# Phase 37 (2026-05-19) — Multi-source omnisearch orchestrator.
#
# Standalone service the new `EverywhereSearchController` calls into.
# Built fresh per the user's strict-independence rule: NO inheritance
# from / sharing with the existing video-only `SearchController#show`,
# NO modification to `Pito::Search.engine`, NO coupling to the existing
# `Pito::Search::Omnisearch` dispatcher or `Game::SearchService`.
#
# R1 (2026-05-25) — Bundles source removed. Two sources remain:
#
#   * games    — `Pito::Search::SearchGames` (unified `games_<env>` index,
#                kind=game discriminator) — returns Game records.
#   * channels — `Pito::Search.engine.search(Channel, ...)` against the
#                dedicated `channels_<env>` index.
#
# Result shape returned by `#call`:
#
#   {
#     query: String,
#     games:    { hits: [Game, ...],    total: Integer, took_ms: Float },
#     channels: { hits: [Channel, ...], total: Integer, took_ms: Float },
#     section_order: [Symbol, Symbol]
#   }
#
# Per-source failures degrade to empty hits with an `:error` key on
# that source's hash — a Meilisearch hiccup on ONE source must not
# blank the whole modal.
#
# Section-order contract:
#   * `/channels*` → [:channels, :games]
#   * `/games*`    → [:games, :channels]
#   * any other    → [:channels, :games]
#     (default — navbar / personal-importance order)
module Pito
  module Search
    class Everywhere
      def initialize(query:, current_path:, page: 1, per_page: 10)
        @query = query.to_s.strip
        @current_path = current_path.to_s
        @page = [ page.to_i, 1 ].max
        @per_page = per_page.to_i.positive? ? per_page.to_i : 10
      end

      def call
        return blank_payload if @query.blank?

        {
          query: @query,
          games: search_games,
          channels: search_channels,
          section_order: section_order
        }
      end

      private

      # Delegates to `Pito::Search::SearchGames` (games-only). The returned
      # `:games` array is Meilisearch ranking + Postgres ILIKE fallback
      # merged uniques, capped at `@per_page`.
      def search_games
        result = Pito::Search::SearchGames.call(
          @query, include_bundles: false, limit: @per_page
        )
        games = Array(result[:games])
        { hits: games, total: games.size, took_ms: 0.0 }
      rescue StandardError => e
        log_failure(:games, e)
        { hits: [], total: 0, took_ms: 0.0, error: e.class.name }
      end

      # Dedicated `channels_<env>` index via the generic engine path.
      # Returns `{ hits: [{ id:, record:, highlights:, score: }, ...],
      # total:, took_ms: }`; we map the `:record` out so the consumer
      # component sees Channel records (matching the games shape).
      def search_channels
        raw = Pito::Search.engine.search(Channel, @query, page: @page, per_page: @per_page)
        records = Array(raw[:hits]).map { |hit| hit[:record] }.compact
        {
          hits: records,
          total: raw[:total].to_i,
          took_ms: raw[:took_ms].to_f
        }
      rescue StandardError => e
        log_failure(:channels, e)
        { hits: [], total: 0, took_ms: 0.0, error: e.class.name }
      end

      def section_order
        if @current_path.start_with?("/channels")
          [ :channels, :games ]
        elsif @current_path.start_with?("/games")
          [ :games, :channels ]
        else
          [ :channels, :games ]
        end
      end

      def blank_payload
        {
          query: "",
          games:    { hits: [], total: 0, took_ms: 0.0 },
          channels: { hits: [], total: 0, took_ms: 0.0 },
          section_order: section_order
        }
      end

      def log_failure(source, error)
        Rails.logger.warn(
          "[Pito::Search::Everywhere] #{source} query failed (#{@query.inspect}): " \
            "#{error.class}: #{error.message}"
        )
      end
    end
  end
end
