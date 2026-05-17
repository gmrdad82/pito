# Omnisearch local-corpus query against the shared `games_<env>`
# Meilisearch index that holds both Game documents (written by
# `Meilisearch::GameIndexer`) and Bundle documents (written by
# `Meilisearch::BundleIndexer`). The two record types coexist in the
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
# `Games::SearchService`) and continues even when the local half is
# empty.
require "net/http"
require "json"

module Meilisearch
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

      { games: games, bundles: bundles }
    rescue StandardError => e
      Rails.logger.warn("[Meilisearch::SearchGames] query failed (#{@query.inspect}): #{e.class}: #{e.message}")
      { games: [], bundles: [] }
    end

    private

    def fetch_hits
      url = ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727")
      uri = URI.parse("#{url}/indexes/#{index_name}/search")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      # Ask for both record types in a single call; we slice them apart
      # by `kind` after the response lands. Hard-cap at 2x the per-kind
      # limit so we have headroom even when results are skewed toward
      # one kind.
      request.body = JSON.generate(
        q: @query,
        limit: @limit * 2
      )

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
    # namespaced `"bundle:<id>"` to coexist with raw game ids in the
    # shared index — strip the prefix to get the AR id.
    def resolve_bundles(hits)
      bundle_ids = hits
        .select { |h| h["kind"] == "bundle" }
        .map { |h| h["id"].to_s.delete_prefix("bundle:").to_i }
        .reject(&:zero?)
      return [] if bundle_ids.empty?

      bundles_by_id = Bundle.where(id: bundle_ids).index_by(&:id)
      bundle_ids.map { |id| bundles_by_id[id] }.compact.first(@limit)
    end
  end
end
