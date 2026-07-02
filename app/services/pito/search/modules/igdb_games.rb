# frozen_string_literal: true

module Pito
  module Search
    module Modules
      # First search module: IGDB main-title game search. Wraps
      # `Game::Igdb::Client#search_games` (main-titles-only `game_type=(0)`,
      # coverless-rejected, denoised) in the standard result envelope, turning
      # IGDB upstream failures into a non-raising `error:` hash.
      #
      # Successful results cache for a day (0.9.0 Phase 7) — repeat searches
      # (typo-retype, re-opened sidebar) answer instantly and spare the 4 req/s
      # IGDB budget; a day-stale catalogue is fine for an import sidebar. Error
      # envelopes are NEVER cached (upstream blips must stay retryable).
      class IgdbGames < Pito::Search::Base
        search_key :igdb_games

        CACHE_TTL = 1.day

        def call(query:, limit: 10)
          q = query.to_s.strip
          return empty if q.empty?

          key    = cache_key(q, limit)
          cached = Rails.cache.read(key)
          return cached if cached

          hits   = ::Game::Igdb::Client.new.search_games(q, limit: limit)
          result = { hits: hits, total: hits.size, error: nil }
          Rails.cache.write(key, result, expires_in: CACHE_TTL)
          result
        rescue ::Game::Igdb::Client::Error => e
          { hits: [], total: 0, error: { kind: "upstream_unavailable", message: e.message } }
        end

        private

        def cache_key(query, limit)
          "pito:igdb-search:v1:#{limit}:#{Digest::SHA256.hexdigest(query.downcase)[0, 32]}"
        end

        def empty
          { hits: [], total: 0, error: nil }
        end
      end
    end
  end
end
