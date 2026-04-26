class CreateChannels < ActiveRecord::Migration[8.1]
  def change
    create_table :channels do |t|
      t.string :youtube_channel_id
      t.string :title
      t.text :description
      t.string :thumbnail_url
      t.integer :subscriber_count
      t.integer :video_count
      t.bigint :view_count
      t.datetime :last_synced_at
      t.text :oauth_access_token
      t.text :oauth_refresh_token
      t.datetime :oauth_expires_at
      t.string :oauth_scopes

      t.timestamps
    end
    add_index :channels, :youtube_channel_id, unique: true
  end
end
