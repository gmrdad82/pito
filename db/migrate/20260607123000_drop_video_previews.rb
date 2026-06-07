class DropVideoPreviews < ActiveRecord::Migration[8.1]
  # VideoPreview was unwired scaffolding for a deferred video-edit/publish
  # pipeline (P32/P33) that will be rethought from scratch. No live code
  # references it (only doc-comments). Drop the table + model. No data.
  def change
    drop_table :video_previews do |t|
      t.string   "category_id"
      t.datetime "created_at", null: false
      t.text     "description"
      t.text     "error_message"
      t.string   "game_title"
      t.datetime "published_at"
      t.integer  "shorts_remixing"
      t.integer  "status", default: 0, null: false
      t.text     "tags", array: true
      t.string   "title"
      t.datetime "updated_at", null: false
      t.bigint   "video_id", null: false
      t.index [ "video_id" ], name: "index_video_previews_on_video_id"
    end
  end
end
