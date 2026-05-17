# 2026-05-18 — Bundle modal "all games" table.
#
# Replaces the prior +N-more overflow shelf that sat below the
# composite cover grid inside the bundle modal. The new section is a
# `.sessions-table`-styled flat table listing EVERY game in the
# bundle (fixed copy "all games", not "+N more"), one row per game,
# columns:
#
#   1. checkbox (placeholder — wired in a later slice)
#   2. title (link to `/games/:id`)
#   3. genre (primary genre label, em-dash when missing)
#   4. release date (short form, em-dash when missing)
#   5. rating score chip (theme-colored, blank when no votes)
#
# The composite cover grid above the table stays unchanged in this
# slice — only the bottom section (overflow shelf) is replaced.
#
# Bundle association loading: title-ordered, eager-loading
# `:primary_genre` so the genre column does not N+1. The heat-bar
# triplet columns sit on `Game` directly so the rating chip needs no
# extra includes.
module Bundles
  class AllGamesTableComponent < ViewComponent::Base
    include GenresHelper

    def initialize(bundle:)
      @bundle = bundle
      @games = bundle.games.includes(:primary_genre).order(:title)
    end

    attr_reader :games

    # Primary-genre display label, em-dash fallback for the column.
    # Reads `Game#primary_genre` (a `belongs_to :primary_genre` on the
    # model — set + recomputed by `GameGenre` callbacks). Distinct
    # from the secondary-genre list shown on the game-show page; this
    # column shows the single canonical primary genre per row.
    def primary_genre_label(game)
      genre_display_name(game.primary_genre).presence || "—"
    end

    # Short, no-time release date for the table column. Matches the
    # `m-d-Y` shape used on the game show page meta row
    # (`app/views/games/show.html.erb` line ~180). Em-dash for missing
    # values so the column reads quiet.
    def short_release_date(game)
      date = game.release_date
      return "—" if date.blank?

      date.strftime("%m-%d-%Y")
    end
  end
end
