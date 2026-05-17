# Phase 27 v2 spec 01 follow-up (2026-05-17) — IGDB-order primary picker.
#
# `Games::PrimaryGenrePicker` previously broke ties alphabetically
# (`LOWER(genres.name) ASC, genres.id ASC`). User feedback (Mandragora —
# IGDB returns `[Role-playing, Adventure, Indie]` but the alphabetical
# winner is "Adventure") flipped the policy: IGDB's per-game genre
# array order IS the primacy order. The first genre in the IGDB payload
# is the canonical primary; alphabetical survives only as a defensive
# fallback when the position column is somehow NULL (legacy rows that
# pre-date this column and that have not been re-synced yet).
#
# This migration adds a nullable `position` integer to `game_genres`.
# Nullable on purpose:
#
#   - Existing rows have no IGDB-array-order context recorded. We
#     could re-fetch every game from IGDB at migration time, but that
#     hits the IGDB rate limiter for thousands of rows. Better to leave
#     them NULL and let the picker's secondary alphabetical fallback
#     drive the choice until the next user-triggered re-sync repopulates
#     `position` for that game.
#   - New rows written by `Igdb::SyncGame#sync_genres` carry an integer
#     position derived from the IGDB payload's array index.
#
# Reversible: `down` drops the column.
class AddPositionToGameGenres < ActiveRecord::Migration[8.1]
  def change
    add_column :game_genres, :position, :integer, null: true
    add_index  :game_genres, [ :game_id, :position ]
  end
end
