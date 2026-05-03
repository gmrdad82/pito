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

ActiveRecord::Schema[8.1].define(version: 2026_05_01_220626) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "bulk_operation_items", force: :cascade do |t|
    t.bigint "bulk_operation_id", null: false
    t.datetime "created_at", null: false
    t.text "error_message"
    t.integer "status", default: 0, null: false
    t.bigint "target_id"
    t.string "target_type"
    t.datetime "updated_at", null: false
    t.bigint "video_id"
    t.index ["bulk_operation_id", "video_id"], name: "index_bulk_operation_items_on_bulk_operation_id_and_video_id", unique: true
    t.index ["bulk_operation_id"], name: "index_bulk_operation_items_on_bulk_operation_id"
    t.index ["target_type", "target_id"], name: "index_bulk_operation_items_on_target_type_and_target_id"
    t.index ["video_id"], name: "index_bulk_operation_items_on_video_id"
  end

  create_table "bulk_operations", force: :cascade do |t|
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.jsonb "dry_run_preview"
    t.integer "kind", null: false
    t.jsonb "parameters"
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.jsonb "target_video_ids"
    t.datetime "updated_at", null: false
  end

  create_table "channels", force: :cascade do |t|
    t.string "channel_url", null: false
    t.boolean "connected", default: false, null: false
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.boolean "star", default: false, null: false
    t.boolean "syncing", default: false, null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["channel_url"], name: "index_channels_on_channel_url", unique: true
    t.index ["last_synced_at"], name: "index_channels_on_last_synced_at"
    t.index ["tenant_id", "connected"], name: "index_channels_on_tenant_id_and_connected"
    t.index ["tenant_id", "star"], name: "index_channels_on_tenant_id_and_star"
    t.index ["tenant_id", "syncing"], name: "index_channels_on_tenant_id_and_syncing"
    t.index ["tenant_id"], name: "index_channels_on_tenant_id"
  end

  create_table "mcp_access_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "last_token_preview", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["token_digest"], name: "index_mcp_access_tokens_on_token_digest", unique: true
  end

  create_table "playlist_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "playlist_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.string "youtube_playlist_item_id", null: false
    t.index ["playlist_id", "video_id"], name: "index_playlist_items_on_playlist_id_and_video_id", unique: true
    t.index ["playlist_id"], name: "index_playlist_items_on_playlist_id"
    t.index ["video_id"], name: "index_playlist_items_on_video_id"
    t.index ["youtube_playlist_item_id"], name: "index_playlist_items_on_youtube_playlist_item_id", unique: true
  end

  create_table "playlists", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "item_count", default: 0, null: false
    t.integer "privacy_status"
    t.datetime "published_at"
    t.string "thumbnail_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "youtube_playlist_id", null: false
    t.index ["channel_id"], name: "index_playlists_on_channel_id"
    t.index ["youtube_playlist_id"], name: "index_playlists_on_youtube_playlist_id", unique: true
  end

  create_table "saved_views", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kind", null: false
    t.string "name", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.citext "url", null: false
    t.index ["kind", "url"], name: "index_saved_views_on_kind_and_url", unique: true
  end

  create_table "tenants", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.datetime "updated_at", null: false
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "password_digest", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.citext "username", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
    t.index ["tenant_id"], name: "index_users_on_tenant_id"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "video_stats", force: :cascade do |t|
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

  create_table "video_uploads", force: :cascade do |t|
    t.bigint "bytes_sent", default: 0, null: false
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "file_name", null: false
    t.bigint "file_size", null: false
    t.integer "privacy_status", default: 0
    t.string "resumable_uri"
    t.integer "status", default: 0, null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id"
    t.string "youtube_video_id"
    t.index ["channel_id"], name: "index_video_uploads_on_channel_id"
    t.index ["video_id"], name: "index_video_uploads_on_video_id"
  end

  create_table "videos", force: :cascade do |t|
    t.integer "category_id"
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.string "default_language"
    t.text "description"
    t.integer "duration_seconds"
    t.datetime "last_synced_at"
    t.boolean "made_for_kids", default: false, null: false
    t.integer "privacy_status"
    t.datetime "published_at"
    t.datetime "scheduled_publish_at"
    t.jsonb "tags"
    t.string "thumbnail_url"
    t.string "title"
    t.datetime "updated_at", null: false
    t.string "youtube_video_id"
    t.index ["channel_id"], name: "index_videos_on_channel_id"
    t.index ["youtube_video_id"], name: "index_videos_on_youtube_video_id", unique: true
  end

  add_foreign_key "bulk_operation_items", "bulk_operations"
  add_foreign_key "bulk_operation_items", "videos"
  add_foreign_key "channels", "tenants"
  add_foreign_key "playlist_items", "playlists"
  add_foreign_key "playlist_items", "videos"
  add_foreign_key "playlists", "channels"
  add_foreign_key "users", "tenants"
  add_foreign_key "video_stats", "videos"
  add_foreign_key "video_uploads", "channels"
  add_foreign_key "video_uploads", "videos"
  add_foreign_key "videos", "channels"
end
