# Phase B (2026-05-19) — Meilisearch indexer for Channel.
#
# Standalone, independent of Meilisearch::GameIndexer /
# Meilisearch::BundleIndexer / the Searchable concern. Channel docs
# live in their OWN physical Meilisearch index (`channels_<env>`),
# not in the shared `games_<env>` corpus that Games + Bundles share.
# Decoupling is deliberate: the Channels search surface evolves on
# its own cadence and must not entangle with the Games index'
# attribute / vector configuration.
#
# Searchable attributes (priority order — Meilisearch weights the
# first entry highest):
#   1. title       — primary search target (channel display name).
#   2. handle      — `@handle` lookup.
#   3. description — channel description body.
#   4. keywords    — channel-author-curated keyword list.
#
# Filterable attributes:
#   id                  — exact-match by integer Channel id.
#   youtube_channel_id  — UC-id extracted from `channel_url`; lets the
#                         search surface resolve a YouTube URL to its
#                         Channel row without a SQL roundtrip.
#   kind                — discriminator string ("channel"). Symmetric
#                         with the games/bundles indexers; useful if a
#                         future unified search surface ever merges
#                         multiple indexes behind a single filter.
#
# Network failures are logged and swallowed — a Meilisearch hiccup
# must not crash the after-commit callback that triggered the index
# job. The retry path is the `pito:meili:reindex_channels` rake task
# or a re-enqueue of `ChannelIndexJob`.
module Meilisearch
  class ChannelIndexer
    SEARCHABLE_ATTRIBUTES = %w[title handle description keywords].freeze
    FILTERABLE_ATTRIBUTES = %w[id youtube_channel_id kind].freeze

    def self.call(channel)
      new(channel).call
    end

    def initialize(channel)
      @channel = channel
    end

    def call
      url = ENV.fetch("MEILISEARCH_URL", "http://127.0.0.1:7727")
      configure_index(url)
      push_document(url)
    rescue StandardError => e
      Rails.logger.warn("[Meilisearch::ChannelIndexer] upsert failed for channel #{@channel.id}: #{e.class}: #{e.message}")
    end

    private

    # Mirrors `Search::Engine#index_name_for` (private) without
    # depending on the engine — keeps the Channel indexer standalone.
    def index_name
      "channels_#{Rails.env}"
    end

    # Idempotent per-call attribute configuration; identical payloads
    # are no-ops on the Meilisearch side.
    def configure_index(url)
      base = "#{url}/indexes/#{index_name}/settings"

      patch_json("#{base}/searchable-attributes", SEARCHABLE_ATTRIBUTES)
      patch_json("#{base}/filterable-attributes", FILTERABLE_ATTRIBUTES)
    end

    def push_document(url)
      # Explicit `?primaryKey=id` for the same reason GameIndexer
      # sets it: the doc carries multiple `*_id` fields (`id`,
      # `youtube_channel_id`) and Meilisearch would otherwise reject
      # the batch with `index_primary_key_multiple_candidates_found`.
      uri = URI.parse("#{url}/indexes/#{index_name}/documents?primaryKey=id")

      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request.body = JSON.generate([ document ])

      http_request(uri, request)
    end

    def document
      {
        id: @channel.id,
        kind: "channel",
        title: @channel.title.to_s,
        handle: @channel.handle.to_s,
        description: @channel.description.to_s.truncate(5000),
        keywords: @channel.keywords.to_s,
        youtube_channel_id: extracted_youtube_channel_id
      }
    end

    # Extracts the UC-id from the locked `channel_url`. Returns nil if
    # the URL doesn't match the Phase 7.5 §11a regex (defensive — the
    # CHANNEL_URL_REGEX validator should prevent this).
    def extracted_youtube_channel_id
      @channel.channel_url.to_s[%r{/channel/(UC[A-Za-z0-9_-]{22})}, 1]
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
