# Omnisearch local-corpus query against the shared `games_<env>`
# Meilisearch index that holds both Game documents (written by
# `Game::MeilisearchIndexer`) and Bundle documents (written by
# `Bundle::MeilisearchIndexer`). The two record types coexist in the
# same physical index and are distinguished by the `kind`
# discriminator field (`"game"` vs `"bundle"`).
#
# Returns a Hash with two keys:
#   - :games   → Array of Game ActiveRecord rows, ordered by
#                Meilisearch's relevance ranking.
#   - :bundles → Array of Bundle ActiveRecord rows, same ordering
#                rule. Empty Array when `include_bundles: false`.
#
# Options:
#   - include_bundles: when true (`:games_search` mode), bundle hits
#                       are included. When false (`:bundle_add` mode),
#                       only game hits.
#   - exclude_bundle:   a Bundle instance whose existing member-game
#                       ids are filtered out of the result set. Used
#                       by `:bundle_add` so already-in-the-bundle
#                       games don't surface as add candidates.
#   - limit:            per-record-type cap. Defaults to 20.
#
# Wire-format note: the same boundary-yes/no convention applies to
# any external boolean (see CLAUDE.md hard rules), but this service
# is internal-only — callers (the Search service + controllers) pass
# native Ruby booleans + ActiveRecord rows.
#
# Network failures are logged and degrade to empty result sets so a
# Meilisearch hiccup never crashes the search controller path. The
# IGDB half of the omnisearch envelope is independent (see
# `Game::SearchService`) and continues even when the local half is
# empty.
require "net/http"
require "json"

module Pito
  module Search
    class SearchGames
      DEFAULT_LIMIT = 20

      def self.call(query, include_bundles: false, exclude_bundle: nil, limit: DEFAULT_LIMIT)
        new(query, include_bundles: include_bundles, exclude_bundle: exclude_bundle, limit: limit).call
      end

      def initialize(query, include_bundles:, exclude_bundle:, limit:)
        @query = query.to_s.strip
        @include_bundles = include_bundles
        @exclude_bundle = exclude_bundle
        @limit = limit
      end

      def call
        return { games: [], bundles: [] } if @query.blank?

        hits = fetch_hits
        games = resolve_games(hits)
        bundles = @include_bundles ? resolve_bundles(hits) : []

        # 2026-05-18 — Postgres ILIKE fallback ALWAYS merged in. The
        # user-reported bug (omnisearch local-results missing for
        # "street fighter" even though "Street Fighter 6" exists locally)
        # reproduces when Meilisearch returns SOME hits (so the prior
        # `if empty?` guard skipped fallback) but those hits don't
        # include a row whose title trivially matches via ILIKE — a
        # symptom of a stale or partially-populated index. Merging the
        # ILIKE fallback uniques after the Meilisearch ordering keeps
        # relevance ranking when the index is populated AND guarantees
        # the obvious substring matches always surface.
        games = merge_with_fallback(games, fallback_games)
        if @include_bundles
          bundles = merge_with_fallback(bundles, fallback_bundles)
        end

        { games: games, bundles: bundles }
      rescue StandardError => e
        Rails.logger.warn("[Pito::Search::SearchGames] query failed (#{@query.inspect}): #{e.class}: #{e.message}")
        # Even on Meilisearch failure, attempt the Postgres fallback so
        # local games are still findable when the search engine is down.
        games = fallback_games
        bundles = @include_bundles ? fallback_bundles : []
        { games: games, bundles: bundles }
      end

      private

      # 2026-05-18 (Bug A fix) — short-query attribute restriction.
      # Meilisearch's default `searchableAttributes` includes
      # `title summary developer_name publisher_name genre_names`, and
      # `prefixSearch: indexingTime` makes every input act as a prefix
      # match. A 2-char query like "st" then matches "starts", "system",
      # "Steam", "studio", etc. inside `summary` / dev / pub / genre
      # fields and surfaces games whose titles have no "st" substring
      # at all (e.g. Pragmata's summary contains "starts").
      #
      # For short queries (<= SHORT_QUERY_THRESHOLD) we restrict the
      # search to the `title` attribute only via `attributesToSearchOn`.
      # That keeps "st" matching to actual title-prefix hits (Street
      # Fighter 6, Star Wars, Stellar Blade, ...) and drops the
      # summary-token noise. Longer queries (>= 4 chars) keep the full
      # attribute set so a user typing a developer / publisher / genre
      # name still gets hits via Meilisearch's default ranking.
      SHORT_QUERY_THRESHOLD = 3

      def fetch_hits
        url = ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727")
        uri = URI.parse("#{url}/indexes/#{index_name}/search")

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        # Ask for both record types in a single call; we slice them apart
        # by `kind` after the response lands. Hard-cap at 2x the per-kind
        # limit so we have headroom even when results are skewed toward
        # one kind.
        body = {
          q: @query,
          limit: @limit * 2
        }
        # Short-query attribute restriction — see SHORT_QUERY_THRESHOLD.
        if @query.length <= SHORT_QUERY_THRESHOLD
          body[:attributesToSearchOn] = [ "title" ]
        end
        request.body = JSON.generate(body)

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https", open_timeout: 2, read_timeout: 4) do |http|
          http.request(request)
        end

        return [] unless response.is_a?(Net::HTTPSuccess)
        JSON.parse(response.body).fetch("hits", [])
      end

      def index_name
        "games_#{Rails.env}"
      end

      # Pulls Game rows in Meilisearch hit order. Filters out games that
      # already belong to `exclude_bundle` (the bundle-add mode caller).
      def resolve_games(hits)
        game_ids = hits.select { |h| h["kind"] == "game" }.map { |h| h["id"] }.compact
        return [] if game_ids.empty?

        if @exclude_bundle
          member_game_ids = @exclude_bundle.bundle_members.pluck(:game_id)
          game_ids -= member_game_ids
        end

        return [] if game_ids.empty?

        games_by_id = Game.where(id: game_ids).index_by(&:id)
        game_ids.map { |id| games_by_id[id] }.compact.first(@limit)
      end

      # Pulls Bundle rows in Meilisearch hit order. Bundle doc ids are
      # namespaced `"bundle_<id>"` to coexist with raw game ids in the
      # shared index — strip the prefix to get the AR id. The legacy
      # `"bundle:<id>"` shape is also accepted defensively in case any
      # stale documents survived from the pre-2026-05-18 broken-insert
      # era (those inserts failed entirely, so in practice this branch
      # is dead — but stripping both is cheaper than worrying about it).
      def resolve_bundles(hits)
        bundle_ids = hits
          .select { |h| h["kind"] == "bundle" }
          .map { |h| h["id"].to_s.delete_prefix("bundle_").delete_prefix("bundle:").to_i }
          .reject(&:zero?)
        return [] if bundle_ids.empty?

        bundles_by_id = Bundle.where(id: bundle_ids).index_by(&:id)
        bundle_ids.map { |id| bundles_by_id[id] }.compact.first(@limit)
      end

      # Merges Meilisearch-ranked results (`primary`) with the Postgres
      # ILIKE fallback (`fallback`). Meilisearch ordering wins for the
      # leading entries; fallback rows whose id is not already in
      # `primary` are appended afterwards, capped at `@limit` total. This
      # guarantees the obvious substring matches always surface even
      # when the Meilisearch index is stale / partially populated, while
      # preserving Meilisearch's relevance ordering when the index is in
      # sync.
      def merge_with_fallback(primary, fallback)
        seen_ids = primary.map(&:id).to_set
        uniques = fallback.reject { |row| seen_ids.include?(row.id) }
        (primary + uniques).first(@limit)
      end

      # Postgres `LOWER(title) ILIKE %q%` OR `igdb_slug ILIKE %q-kebab%`
      # OR alt-name ILIKE fallback for the games half of the envelope.
      # Always consulted (and merged with the Meilisearch hits via
      # `merge_with_fallback`) so the obvious substring matches surface
      # even when the index is stale.
      #
      # Three columns matched:
      #
      #   1. `title`               — the IGDB `name` field as-persisted.
      #                              Can be localized / non-English / an
      #                              edition variant.
      #   2. `igdb_slug`           — IGDB canonical lowercased kebab-case
      #                              slug. "street fighter" dasherizes
      #                              to "street-fighter" so multi-word
      #                              inputs match slugs like
      #                              `street-fighter-6`. Single-word
      #                              queries dasherize to themselves.
      #   3. `alternative_names`   — 2026-05-19. Postgres text[] column
      #                              populated from IGDB's
      #                              `alternative_names` array (e.g.
      #                              "SF6", "FF7 Rebirth", "TotK"). The
      #                              `EXISTS (SELECT 1 FROM unnest(...)
      #                              AS alt WHERE LOWER(alt) ILIKE ?)`
      #                              pattern is Postgres-specific and
      #                              uses the column's GIN index when
      #                              the planner picks it up.
      #
      # The result set is title-ordered so the fallback feels
      # deterministic. `exclude_bundle` still applies — already-in-bundle
      # games are filtered out so the `:bundle_add` flow never
      # re-surfaces members.
      def fallback_games
        title_like = "%#{Game.sanitize_sql_like(@query.downcase)}%"
        slug_like  = "%#{Game.sanitize_sql_like(@query.downcase.tr(' ', '-'))}%"
        scope = Game.where(
          "LOWER(title) ILIKE :title_q OR LOWER(igdb_slug) ILIKE :slug_q OR EXISTS (SELECT 1 FROM unnest(alternative_names) AS alt WHERE LOWER(alt) ILIKE :title_q)",
          title_q: title_like, slug_q: slug_like
        )
        if @exclude_bundle
          member_game_ids = @exclude_bundle.bundle_members.pluck(:game_id)
          scope = scope.where.not(id: member_game_ids) if member_game_ids.any?
        end
        scope.order(:title).limit(@limit).to_a
      end

      # Postgres `LOWER(name) ILIKE %q%` OR `LOWER(slug) ILIKE %q-kebab%`
      # fallback for the bundles half of the envelope. Only consulted
      # when `include_bundles: true` (i.e. `:games_search` mode). Both
      # columns are matched for the same reason `fallback_games` matches
      # title + slug — the user-facing name may diverge from the
      # canonical slug (rename history, alt-name input). Name-ordered
      # for deterministic output.
      def fallback_bundles
        name_like = "%#{Bundle.sanitize_sql_like(@query.downcase)}%"
        slug_like = "%#{Bundle.sanitize_sql_like(@query.downcase.tr(' ', '-'))}%"
        Bundle.where(
          "LOWER(name) ILIKE ? OR LOWER(slug) ILIKE ?",
          name_like, slug_like
        ).order(:name).limit(@limit).to_a
      end
    end
  end
end
