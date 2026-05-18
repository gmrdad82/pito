# Phase 34 (2026-05-18) — Meilisearch indexer for Bundle.
#
# Pushes one Bundle's searchable document into the SAME
# `games_#{Rails.env}` index that `Meilisearch::GameIndexer` writes
# Game docs into. Single corpus → one search query at the UI layer.
# The two record types are distinguished by the `kind` discriminator
# field (`"game"` vs `"bundle"`).
#
# Document id is namespaced (`"bundle_<id>"`) to avoid colliding with
# Game ids in the shared index. Game docs continue to use the raw
# numeric id as their primary key; Bundle docs prefix. The underscore
# separator is mandated by Meilisearch's document-id charset rule
# (`[a-zA-Z0-9_-]` only); see `composite_id` comment for context.
#
# Vector payload: when an embedding is supplied (from
# `Bundles::VoyageIndexer` via `Voyage::Client`), it is attached as
# `_vectors.default` so Meilisearch's hybrid surface can rank by
# vector similarity. The embedding is also written to the
# `bundles.summary_embedding` pgvector column by the caller — passing
# it inline here avoids a redundant DB read.
#
# Index configuration (searchable / filterable / sortable attribute
# lists) is owned by `Meilisearch::GameIndexer` — both indexers write
# to the same physical index, and the Game side is the canonical
# configurer. The bundle-only attributes (`kind`, `game_count`) join
# the filterable / sortable lists there.
#
# Network failures are logged and swallowed — a Meilisearch hiccup
# must not crash the Voyage indexer that triggered it. The retry path
# is the rake task (`pito:voyage:reindex_bundles` /
# `pito:voyage:reindex_all`) or a re-enqueue of `BundleVoyageIndexJob`.
module Meilisearch
  class BundleIndexer
    def self.call(bundle, embedding: nil)
      new(bundle, embedding: embedding).call
    end

    def initialize(bundle, embedding: nil)
      @bundle = bundle
      @embedding = embedding
    end

    def call
      url = ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727")
      push_document(url)
    rescue StandardError => e
      Rails.logger.warn("[Meilisearch::BundleIndexer] upsert failed for bundle #{@bundle.id}: #{e.class}: #{e.message}")
    end

    private

    def index_name
      "games_#{Rails.env}"
    end

    def composite_id
      # 2026-05-18 (DR follow-up #2) — separator MUST be `_` (or `-`),
      # NOT `:`. Meilisearch rejects document identifiers containing
      # any character outside `[a-zA-Z0-9_-]` (max 511 bytes), so the
      # previous `"bundle:#{id}"` shape failed every insert with
      # `Document identifier "bundle:3" is invalid`. The underscore
      # variant still namespaces the bundle id away from raw integer
      # Game ids in the shared `games_<env>` index, and remains
      # trivially parseable on the way out (`split("_", 2)`).
      "bundle_#{@bundle.id}"
    end

    def push_document(url)
      # 2026-05-18 (DR follow-up #2) — explicit `?primaryKey=id` is
      # MANDATORY. The bundle document also carries multiple `*_id`
      # fields (`id`, `bundle_id`), and without an explicit primary
      # key Meilisearch rejects the entire batch with
      # `index_primary_key_multiple_candidates_found`. See the longer
      # comment in `Meilisearch::GameIndexer#push_document` — both
      # indexers write to the same `games_<env>` physical index, so
      # the primary key MUST match (`id`) across both.
      uri = URI.parse("#{url}/indexes/#{index_name}/documents?primaryKey=id")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate([ document ])

      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https") do |http|
        http.request(request)
      end
    end

    def document
      doc = {
        id: composite_id,
        kind: "bundle",
        bundle_id: @bundle.id,
        title: @bundle.name.to_s,
        summary: aggregated_summary,
        game_count: @bundle.games.size
      }

      vector = @embedding || (@bundle.respond_to?(:summary_embedding) ? @bundle.summary_embedding : nil)
      doc[:_vectors] = { default: vector } if vector.present?

      doc
    end

    # Concatenate up to 5 member-game summaries (em-dash joined, same
    # separator the `Games::VoyageIndexer` uses for the title/summary
    # combination). Truncating at 5 keeps the Meilisearch doc bounded
    # for a large bundle without losing its distinguishing keywords;
    # the rest of the corpus picks up the per-game terms via the
    # individual Game docs.
    def aggregated_summary
      @bundle.games.first(5).map(&:summary).compact.reject(&:blank?).join(" — ")
    end
  end
end
