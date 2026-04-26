class CreateVideoUploads < ActiveRecord::Migration[8.1]
  def change
    create_table :video_uploads do |t|
      t.references :channel, null: false, foreign_key: true
      t.references :video, foreign_key: true
      t.integer :status, null: false, default: 0
      t.string :title, null: false
      t.text :description
      t.integer :privacy_status, default: 0
      t.string :resumable_uri
      t.string :file_name, null: false
      t.bigint :file_size, null: false
      t.bigint :bytes_sent, default: 0, null: false
      t.string :youtube_video_id
      t.text :error_message

      t.timestamps
    end
  end
end
