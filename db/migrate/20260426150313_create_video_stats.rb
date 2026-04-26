class CreateVideoStats < ActiveRecord::Migration[8.1]
  def change
    create_table :video_stats do |t|
      t.references :video, null: false, foreign_key: true
      t.date :date
      t.integer :views
      t.integer :likes
      t.integer :comments
      t.integer :shares
      t.float :watch_time_minutes
      t.float :average_view_duration_seconds
      t.float :average_view_percentage
      t.integer :subscribers_gained
      t.integer :subscribers_lost

      t.timestamps
    end
    add_index :video_stats, [ :video_id, :date ], unique: true
  end
end
