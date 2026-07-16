# frozen_string_literal: true

module Games
  # POST /games/search
  #
  # Searches IGDB for games matching the given query.
  # Delegates to `Pito::Search::Modules::IgdbGames` (the same module used
  # throughout the search stack) so the response is the standard error-envelope
  # shape: `{ hits: [...], error: nil | { kind:, message: } }`.
  #
  # Request body (JSON):
  #   { "query": "Hollow Knight", "limit": 25 }
  #
  # Response (JSON):
  #   { "hits": [ { "id":, "name":, "cover": { "url": } }, … ],
  #     "error": null | { "kind": "upstream_unavailable", "message": "…" },
  #     "library_ids": [1234, 5678]   # igdb_ids already in the local DB
  #   }
  #
  # Auth: authenticated_only (unauthenticated → 401).
  class SearchController < ApplicationController
    # Auth is handled by Sessions::AuthConcern (authenticate_session! before_action
    # from ApplicationController). Unauthenticated requests are redirected to root.
    # No `allow_anonymous` declared here → all actions require authentication.

    def create
      query = params[:query].to_s.strip
      # `limit` (the pito-tui import sidebar's viewport-driven hit count,
      # owner 2026-07-15) is honored via client_page_limit — clamped to the
      # :games tool's max_page_size; absent/invalid falls back to
      # IgdbGames::DEFAULT_LIMIT (unchanged pre-limit behavior).
      limit = client_page_limit(tool: :games, default: Pito::Search::Modules::IgdbGames::DEFAULT_LIMIT)
      result = Pito::Search::Modules::IgdbGames.new.call(query: query, limit: limit)

      # Augment hits with an in_library flag resolved against the local DB.
      # Return library_ids separately so the client can apply the marker
      # without a hit-by-hit payload change.
      library_ids = igdb_ids_in_library(result[:hits])

      render json: {
        hits:        annotate_type_notes(result[:hits]),
        error:       result[:error],
        library_ids: library_ids
      }
    end

    private

    def igdb_ids_in_library(hits)
      ids = hits.map { |h| h["id"] || h[:id] }.compact
      return [] if ids.empty?
      ::Game.where(igdb_id: ids).pluck(:igdb_id)
    end

    # Stamp a witty "(remake)" / "(remaster)" note on re-release hits so the
    # client can flag them in cyan — the original and its remake both surface
    # now (see Game::Igdb::Client::DEFAULT_SEARCH_GAME_TYPES), so the user can
    # tell them apart at a glance. Main games get no note.
    def annotate_type_notes(hits)
      Array(hits).map do |hit|
        note = case hit["game_type"] || hit[:game_type]
        when ::Game::Igdb::Client::GAME_TYPE_REMAKE   then Pito::Copy.render("pito.copy.search.remake")
        when ::Game::Igdb::Client::GAME_TYPE_REMASTER then Pito::Copy.render("pito.copy.search.remaster")
        end
        note ? hit.merge("type_note" => note) : hit
      end
    end
  end
end
