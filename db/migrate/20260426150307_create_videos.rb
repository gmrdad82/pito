class CreateVideos < ActiveRecord::Migration[8.1]
  def change
    create_table :videos do |t|
      t.references :channel, null: false, foreign_key: true
      t.string :youtube_video_id
      t.string :title
      t.text :description
      t.datetime :published_at
      t.integer :duration_seconds
      t.string :thumbnail_url
      t.json :tags
      t.datetime :last_synced_at

      t.timestamps
    end
    add_index :videos, :youtube_video_id, unique: true
  end
end
