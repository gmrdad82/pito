# Phase 27 follow-up (2026-05-11) — single-primary-genre pointer for
# the `/games` Genres outer-shelf. Picks ONE canonical genre per game so
# a multi-genre row appears in exactly one sub-shelf instead of every
# `game_genres` join (the prior fallback documented in
# `_genre_sub_shelf.html.erb`).
#
# The column is nullable: a fresh game with no genres yet (or a not-yet
# synced row) holds `NULL`. `Game#before_save :assign_primary_genre_if_blank`
# fills it on first save when at least one linked genre exists; the
# `pito:backfill_primary_genres` rake task backfills existing rows.
class AddPrimaryGenreIdToGames < ActiveRecord::Migration[8.1]
  def change
    add_reference :games, :primary_genre,
                  foreign_key: { to_table: :genres, on_delete: :nullify },
                  null: true,
                  index: true
  end
end
