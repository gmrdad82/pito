# Phase 37 (2026-05-19) — Multi-source omnisearch orchestrator.
#
# Standalone service the new `EverywhereSearchController` calls into.
# Built fresh per the user's strict-independence rule: NO inheritance
# from / sharing with the existing video-only `SearchController#show`,
# NO modification to `Search.engine`, NO coupling to the existing
# `Search::Omnisearch` dispatcher or `Games::SearchService`.
#
# Three sources, queried independently:
#
#   * games    — `Meilisearch::SearchGames` (unified `games_<env>` index,
#                kind=game discriminator) — returns Game records.
#   * bundles  — `Meilisearch::SearchGames` (same unified call, kind=bundle
#                discriminator + `include_bundles: true`) — returns Bundle
#                records.
#   * channels — `Search.engine.search(Channel, ...)` against the
#                dedicated `channels_<env>` index.
#
# Why two different surfaces (orchestrator-internal note):
#   * Games + Bundles share ONE physical Meilisearch index distinguished
#     by a `kind` field, with bundle docs carrying a namespaced
#     `"bundle_<id>"` primary key. The generic `Search.engine.search`
#     path derives the index name from the model class, so calling it
#     with `Bundle` would target a `bundles_<env>` index that does not
#     exist, and the `deserialize_hit` `find_by(id:)` step cannot resolve
#     namespaced string ids back to Bundle rows. `Meilisearch::SearchGames`
#     already handles this split correctly (per `kind`, with id stripping
#     for bundles, plus a Postgres ILIKE fallback). Reusing it preserves
#     the orchestrator's "query each source independently" intent without
#     re-implementing the existing split logic.
#   * Channels live in their OWN `channels_<env>` index (per the Channel
#     indexer's standalone design), so `Search.engine.search(Channel, ...)`
#     resolves naturally.
#
# Result shape returned by `#call`:
#
#   {
#     query: String,
#     games:    { hits: [Game, ...],    total: Integer, took_ms: Float },
#     bundles:  { hits: [Bundle, ...],  total: Integer, took_ms: Float },
#     channels: { hits: [Channel, ...], total: Integer, took_ms: Float },
#     section_order: [Symbol, Symbol, Symbol]
#   }
#
# Per-source failures degrade to empty hits with an `:error` key on
# that source's hash — a Meilisearch hiccup on ONE source must not
# blank the whole modal.
#
# Section-order contract:
#   * `/channels*` → [:channels, :games, :bundles]
#   * `/games*`    → [:games, :bundles, :channels]
#   * any other    → [:channels, :games, :bundles]
#     (default — navbar / personal-importance order)
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
        bundles: search_bundles,
        channels: search_channels,
        section_order: section_order
      }
    end

    private

    # Delegates to `Meilisearch::SearchGames` with `include_bundles:
    # false` (games-only). The returned `:games` array is Meilisearch
    # ranking + Postgres ILIKE fallback merged uniques, capped at
    # `@per_page`. `:total` mirrors the array length — Meilisearch's
    # estimated-total figure is not surfaced by SearchGames; the cap is
    # the practical ceiling the UI shows anyway.
    def search_games
      result = Meilisearch::SearchGames.call(
        @query, include_bundles: false, limit: @per_page
      )
      games = Array(result[:games])
      { hits: games, total: games.size, took_ms: 0.0 }
    rescue StandardError => e
      log_failure(:games, e)
      { hits: [], total: 0, took_ms: 0.0, error: e.class.name }
    end

    # Delegates to `Meilisearch::SearchGames` with `include_bundles:
    # true` and slices off the `:bundles` half of the envelope. The
    # `:games` half is discarded here because `search_games` already
    # owns that source — two calls to SearchGames keep the per-source
    # error isolation intact (a bundle-side failure must not blank the
    # games section and vice versa).
    def search_bundles
      result = Meilisearch::SearchGames.call(
        @query, include_bundles: true, limit: @per_page
      )
      bundles = Array(result[:bundles])
      { hits: bundles, total: bundles.size, took_ms: 0.0 }
    rescue StandardError => e
      log_failure(:bundles, e)
      { hits: [], total: 0, took_ms: 0.0, error: e.class.name }
    end

    # Dedicated `channels_<env>` index via the generic engine path.
    # Returns `{ hits: [{ id:, record:, highlights:, score: }, ...],
    # total:, took_ms: }`; we map the `:record` out so the consumer
    # component sees Channel records (matching the games + bundles
    # shape).
    def search_channels
      raw = Search.engine.search(Channel, @query, page: @page, per_page: @per_page)
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
        [ :channels, :games, :bundles ]
      elsif @current_path.start_with?("/games")
        [ :games, :bundles, :channels ]
      else
        [ :channels, :games, :bundles ]
      end
    end

    def blank_payload
      {
        query: "",
        games:    { hits: [], total: 0, took_ms: 0.0 },
        bundles:  { hits: [], total: 0, took_ms: 0.0 },
        channels: { hits: [], total: 0, took_ms: 0.0 },
        section_order: section_order
      }
    end

    def log_failure(source, error)
      Rails.logger.warn(
        "[Search::Everywhere] #{source} query failed (#{@query.inspect}): " \
          "#{error.class}: #{error.message}"
      )
    end
  end
end
