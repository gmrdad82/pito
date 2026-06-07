# frozen_string_literal: true

module Pito
  module Search
    module Modules
      # First search module: IGDB main-title game search. Wraps
      # `Game::Igdb::Client#search_games` (main-titles-only `game_type=(0)`,
      # coverless-rejected, denoised) in the standard result envelope, turning
      # IGDB upstream failures into a non-raising `error:` hash.
      class IgdbGames < Pito::Search::Base
        search_key :igdb_games

        def call(query:, limit: 10)
          q = query.to_s.strip
          return empty if q.empty?

          hits = ::Game::Igdb::Client.new.search_games(q, limit: limit)
          { hits: hits, total: hits.size, error: nil }
        rescue ::Game::Igdb::Client::Error => e
          { hits: [], total: 0, error: { kind: "upstream_unavailable", message: e.message } }
        end

        private

        def empty
          { hits: [], total: 0, error: nil }
        end
      end
    end
  end
end
