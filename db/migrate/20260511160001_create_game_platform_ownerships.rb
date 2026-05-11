# Phase 27 §1a — per-platform ownership join.
#
# Replaces the single-valued `games.platform_owned_id` pointer with a
# multi-valued (game, platform) join carrying ownership metadata
# (`acquired_at`, `store`, `notes`). Unique on `(game_id, platform_id)`
# so a single game can't claim the same platform twice. Cascade-on-
# delete from games (deleting a game wipes its ownership rows);
# restrict-on-delete from platforms (a platform with active ownerships
# cannot be deleted — platforms are append-only, the IGDB sync upserts
# but never destroys).
class CreateGamePlatformOwnerships < ActiveRecord::Migration[8.1]
  def change
    create_table :game_platform_ownerships do |t|
      t.references :game,     null: false, foreign_key: { on_delete: :cascade }
      t.references :platform, null: false, foreign_key: { on_delete: :restrict }
      t.datetime :acquired_at
      t.string   :store
      t.text     :notes
      t.timestamps

      t.index [ :game_id, :platform_id ], unique: true,
                                          name: "index_game_platform_ownerships_uniqueness"
    end
  end
end
