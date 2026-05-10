# Phase 14 §1 — `game_genres`, `game_platforms`, `game_developers`,
# `game_publishers` join tables.
#
# Composite uniqueness on `(game_id, <reference>_id)` for each. FKs
# cascade so deleting a Game wipes its joins.
class CreateGameJoinTables < ActiveRecord::Migration[8.1]
  def change
    create_table :game_genres do |t|
      t.references :game,  null: false, foreign_key: { on_delete: :cascade }
      t.references :genre, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps

      t.index [ :game_id, :genre_id ], unique: true
    end

    create_table :game_platforms do |t|
      t.references :game,     null: false, foreign_key: { on_delete: :cascade }
      t.references :platform, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps

      t.index [ :game_id, :platform_id ], unique: true
    end

    create_table :game_developers do |t|
      t.references :game,    null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps

      t.index [ :game_id, :company_id ], unique: true
    end

    create_table :game_publishers do |t|
      t.references :game,    null: false, foreign_key: { on_delete: :cascade }
      t.references :company, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps

      t.index [ :game_id, :company_id ], unique: true
    end
  end
end
