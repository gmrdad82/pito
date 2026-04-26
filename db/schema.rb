# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_04_26_221118) do
  create_table "app_settings", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "channels", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.boolean "connected", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.datetime "last_synced_at"
    t.text "oauth_access_token"
    t.datetime "oauth_expires_at"
    t.text "oauth_refresh_token"
    t.string "oauth_scopes"
    t.integer "subscriber_count"
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "video_count"
    t.bigint "view_count"
    t.string "youtube_channel_id"
    t.index ["youtube_channel_id"], name: "index_channels_on_youtube_channel_id", unique: true
  end

  create_table "video_stats", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.float "average_view_duration_seconds"
    t.float "average_view_percentage"
    t.integer "comments"
    t.datetime "created_at", null: false
    t.date "date"
    t.integer "likes"
    t.integer "shares"
    t.integer "subscribers_gained"
    t.integer "subscribers_lost"
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.integer "views"
    t.float "watch_time_minutes"
    t.index ["video_id", "date"], name: "index_video_stats_on_video_id_and_date", unique: true
    t.index ["video_id"], name: "index_video_stats_on_video_id"
  end

  create_table "videos", charset: "utf8mb4", collation: "utf8mb4_unicode_ci", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.datetime "last_synced_at"
    t.datetime "published_at"
    t.json "tags"
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "youtube_video_id"
    t.index ["channel_id"], name: "index_videos_on_channel_id"
    t.index ["youtube_video_id"], name: "index_videos_on_youtube_video_id", unique: true
  end

  add_foreign_key "video_stats", "videos"
  add_foreign_key "videos", "channels"
end
