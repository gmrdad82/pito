class CreatePlaylistItems < ActiveRecord::Migration[8.1]
  def change
    create_table :playlist_items do |t|
      t.references :playlist, null: false, foreign_key: true
      t.references :video, null: false, foreign_key: true
      t.string :youtube_playlist_item_id, null: false
      t.integer :position, default: 0, null: false

      t.timestamps
    end

    add_index :playlist_items, :youtube_playlist_item_id, unique: true
    add_index :playlist_items, [ :playlist_id, :video_id ], unique: true
  end
end
