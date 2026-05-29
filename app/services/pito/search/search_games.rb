# Omnisearch local-corpus query against the shared `games_<env>`
# Meilisearch index that holds Game documents (written by
# `Game::MeilisearchIndexer`). The `kind` discriminator field is
# `"game"`.
#
# R1 (2026-05-25) — bundle documents removed; games only.
#
# Returns a Hash with one key:
#   - :games   → Array of Game ActiveRecord rows, ordered by
#                Meilisearch's relevance ranking.
#
# Options:
#   - limit: per-record-type cap. Defaults to 20.
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

      def self.call(query, limit: DEFAULT_LIMIT, **_ignored)
        new(query, limit: limit).call
      end

      def initialize(query, limit: DEFAULT_LIMIT)
        @query = query.to_s.strip
        @limit = limit
      end

      def call
        return { games: [] } if @query.blank?

        { games: search_games }
      rescue StandardError => e
        Rails.logger.warn("[Pito::Search::SearchGames] query failed (#{@query.inspect}): #{e.class}: #{e.message}")
        { games: [] }
      end

      private

      def search_games
        title_like = "%#{Game.sanitize_sql_like(@query.downcase)}%"
        slug_like  = "%#{Game.sanitize_sql_like(@query.downcase.tr(' ', '-'))}%"
        Game.where(
          "LOWER(title) ILIKE :title_q OR LOWER(igdb_slug) ILIKE :slug_q OR EXISTS (SELECT 1 FROM unnest(alternative_names) AS alt WHERE LOWER(alt) ILIKE :title_q)",
          title_q: title_like, slug_q: slug_like
        ).order(:title).limit(@limit).to_a
      end
    end
  end
end
