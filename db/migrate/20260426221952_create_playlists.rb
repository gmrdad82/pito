class CreatePlaylists < ActiveRecord::Migration[8.1]
  def change
    create_table :playlists do |t|
      t.references :channel, null: false, foreign_key: true
      t.string :youtube_playlist_id, null: false
      t.string :title, null: false
      t.text :description
      t.integer :privacy_status
      t.integer :item_count, default: 0, null: false
      t.string :thumbnail_url
      t.datetime :published_at

      t.timestamps
    end

    add_index :playlists, :youtube_playlist_id, unique: true
  end
end
