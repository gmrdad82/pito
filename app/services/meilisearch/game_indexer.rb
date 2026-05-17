# Phase 34 (2026-05-18) — Meilisearch indexer for Game.
#
# Pushes one Game's searchable document into the
# `games_#{Rails.env}` index. The index name follows the project
# convention enforced in `Search::Engine#index_name_for` (model name
# underscored + pluralized + per-env suffix), so the same physical
# index that the eventual `Game` Searchable surface will hit is the
# one this service writes to.
#
# The same index ALSO holds Bundle documents (written by
# `Meilisearch::BundleIndexer`) — single corpus, one query at the UI
# layer. The two record types are distinguished by the `kind`
# discriminator (`"game"` vs `"bundle"`). Game docs keep their raw
# numeric `id` as the primary key; Bundle docs use a namespaced
# `"bundle:<id>"` to avoid collisions.
#
# First-write self-configures the index: on every call we update the
# searchable + filterable + sortable attribute lists. Meilisearch's
# `update_*_attributes` endpoints are idempotent — a no-op repeat
# costs a queued task but no actual rebuild. We do this on every
# write rather than only first-write because the attribute lists
# evolve with the codebase and we want the index to track without
# requiring an explicit "configure" step. The reindex rake task
# (`pito:voyage:reindex_games` / `pito:voyage:reindex_all`) hits
# this same code path.
#
# Searchable attributes (in priority order — Meilisearch weights the
# first entry highest):
#   1. title      — primary search target.
#   2. summary    — secondary text body.
#
# Filterable attributes (for "filter by" support in the search
# surface):
#   id, igdb_id, igdb_slug, release_year, primary_genre_id, kind,
#   bundle_id, game_count.
#
# Sortable attributes:
#   release_year, total_rating, igdb_synced_at, game_count.
#
# Vector payload: when the Game has a `summary_embedding`, it is
# attached as `_vectors.default` so Meilisearch's hybrid search can
# rank by vector similarity. The vector itself comes from
# `Voyage::Client` via `Games::VoyageIndexer`; this service does not
# call Voyage directly.
#
# Network failures are logged and swallowed — a Meilisearch hiccup
# must not crash the Voyage indexer or the IGDB sync that triggered
# it. The retry path is the rake task (`pito:voyage:reindex_games`)
# or a re-enqueue of `GameVoyageIndexJob`.
module Meilisearch
  class GameIndexer
    SEARCHABLE_ATTRIBUTES = %w[title summary].freeze
    FILTERABLE_ATTRIBUTES = %w[id igdb_id igdb_slug release_year primary_genre_id kind bundle_id game_count].freeze
    SORTABLE_ATTRIBUTES   = %w[release_year total_rating igdb_synced_at game_count].freeze

    def self.call(game)
      new(game).call
    end

    def initialize(game)
      @game = game
    end

    def call
      url = ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727")
      configure_index(url)
      push_document(url)
    rescue StandardError => e
      Rails.logger.warn("[Meilisearch::GameIndexer] upsert failed for game #{@game.id}: #{e.class}: #{e.message}")
    end

    private

    def index_name
      "games_#{Rails.env}"
    end

    # Idempotent per-call attribute configuration. Each request
    # queues a Meilisearch task; repeats with identical payloads are
    # no-ops on the engine side.
    def configure_index(url)
      base = "#{url}/indexes/#{index_name}/settings"

      patch_json("#{base}/searchable-attributes", SEARCHABLE_ATTRIBUTES)
      patch_json("#{base}/filterable-attributes", FILTERABLE_ATTRIBUTES)
      patch_json("#{base}/sortable-attributes",   SORTABLE_ATTRIBUTES)
    end

    def push_document(url)
      uri = URI.parse("#{url}/indexes/#{index_name}/documents")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate([ document ])

      http_request(uri, request)
    end

    def document
      doc = {
        id: @game.id,
        kind: "game",
        title: @game.title.to_s,
        summary: @game.summary.to_s,
        igdb_id: @game.igdb_id,
        igdb_slug: @game.igdb_slug,
        release_year: @game.release_year,
        primary_genre_id: @game.primary_genre_id
      }

      # The `summary_embedding` column is added by
      # `AddSummaryEmbeddingToGames` (Phase 34). The `respond_to?`
      # guard keeps boot resilient if the migration hasn't yet
      # landed in a given environment.
      if @game.respond_to?(:summary_embedding) && @game.summary_embedding.present?
        doc[:_vectors] = { default: @game.summary_embedding }
      end

      doc
    end

    def patch_json(url, body)
      uri = URI.parse(url)
      request = Net::HTTP::Put.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate(body)
      http_request(uri, request)
    end

    def http_request(uri, request)
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    end
  end
end
