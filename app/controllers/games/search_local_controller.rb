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
      if q.blank?
        # Clearing the search restores page 1 AND the pager sentinel — a
        # bare rows render here used to strand the picker capped at 50.
        games, next_cursor = Game.picker_page
        render partial: "games/picker_reset", locals: { games:, next_cursor: }
      else
        games = Game.where("title ILIKE ?", "%#{q}%").order(:title).limit(50)
        render partial: "games/picker_rows", locals: { games: games }
      end
    end
  end
end
