# frozen_string_literal: true

class DropGamePlatformOwnerships < ActiveRecord::Migration[8.1]
  def up
    drop_table :game_platform_ownerships
  end

  def down
    create_table :game_platform_ownerships do |t|
      t.references :game, null: false, foreign_key: { on_delete: :cascade }
      t.text :platform_token, null: false
      t.timestamps
    end

    add_index :game_platform_ownerships, [ :game_id, :platform_token ],
              unique: true,
              name: "index_game_platform_ownerships_on_game_id_and_platform_token"

    add_check_constraint :game_platform_ownerships,
                         "platform_token = ANY (ARRAY['ps'::text, 'switch'::text, 'steam'::text])",
                         name: "game_platform_ownerships_platform_token_allowlist"
  end
end
