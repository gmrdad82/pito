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
  #   { "query": "Hollow Knight" }
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
      result = Pito::Search::Modules::IgdbGames.new.call(query: query)

      # Augment hits with an in_library flag resolved against the local DB.
      # Return library_ids separately so the client can apply the marker
      # without a hit-by-hit payload change.
      library_ids = igdb_ids_in_library(result[:hits])

      render json: {
        hits:        result[:hits],
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
  end
end
