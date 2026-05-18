# 2026-05-18 — FN2 (user-added platform ownership). The
# `game_platforms` join carries the IGDB-reported "this game ships on
# platform X" set. Users can now also manually mark a game as
# available on PS / Switch / Steam from `/games/:id` even when IGDB
# does not list the platform. To keep IGDB sync from clobbering
# user-added rows (FN3), each row tracks its origin.
#
# `source` enum values:
#   - "igdb"  (default) — created by `Igdb::SyncGame#sync_platforms`.
#   - "user"             — created by `Games::OwnershipTogglesController`
#                          when the user flips `[owned]` for a chip
#                          whose canonical platform is not yet in
#                          `game.platforms_available`.
#
# All existing rows backfill to "igdb" via the `default: "igdb"`
# clause — they were all created by the IGDB sync prior to this
# migration.
class AddSourceToGamePlatforms < ActiveRecord::Migration[8.1]
  def change
    add_column :game_platforms, :source, :string, default: "igdb", null: false
    add_index  :game_platforms, :source
  end
end
