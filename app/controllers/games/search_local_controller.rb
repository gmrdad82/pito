# frozen_string_literal: true

module Games
  # POST /games/search-local
  #
  # Searches the local Game table for games whose title matches the query.
  # Returns HTML row markup for the games picker sidebar list — the JS swaps
  # the `data-pito--games-nav-target="list"` container's innerHTML with it.
  #
  # Request params:
  #   q — String; blank returns first 50 games ordered by title
  #
  # Response:
  #   text/html — .pito-game-row elements (no wrapping container, no layout)
  #
  # Auth: requires authentication (no allow_anonymous declared).
  class SearchLocalController < ApplicationController
    def create
      q = params[:q].to_s.strip
      games = if q.blank?
        Game.order(:title).limit(50)
      else
        Game.where("title ILIKE ?", "%#{q}%").order(:title).limit(50)
      end

      render partial: "games/picker_rows", locals: { games: games }
    end
  end
end
