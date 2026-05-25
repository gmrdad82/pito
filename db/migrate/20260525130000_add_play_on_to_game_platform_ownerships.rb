# B7 — play_on flag on game_platform_ownerships.
#
# Adds a boolean `play_on` column (default false, not null) to mark
# which single ownership row the user intends to play the game on.
# The partial unique index enforces exactly one TRUE per game at the
# DB level. The model-layer callback auto-sets the flag for the first
# ownership created per game.
class AddPlayOnToGamePlatformOwnerships < ActiveRecord::Migration[8.0]
  def change
    add_column :game_platform_ownerships, :play_on, :boolean,
               default: false, null: false

    add_index :game_platform_ownerships,
              [ :game_id, :play_on ],
              unique: true,
              where: "play_on = true",
              name: "index_game_platform_ownerships_unique_play_on_per_game"
  end
end
