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

ActiveRecord::Schema[8.1].define(version: 2026_05_04_233708) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "vector"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "key"
    t.datetime "updated_at", null: false
    t.text "value"
    t.text "voyage_api_key"
    t.boolean "voyage_index_project_notes", default: false, null: false
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

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", default: "Untitled collection", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_collections_on_tenant_id_and_name"
    t.index ["tenant_id"], name: "index_collections_on_tenant_id"
  end

  create_table "footages", force: :cascade do |t|
    t.string "aspect_ratio"
    t.integer "audio_track_count"
    t.integer "bit_depth", default: 8, null: false
    t.string "codec"
    t.string "color_profile"
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.string "filename", null: false
    t.decimal "fps", precision: 6, scale: 3
    t.bigint "game_id"
    t.boolean "has_commentary_track", default: false, null: false
    t.integer "kind", null: false
    t.string "local_path", null: false
    t.string "nas_path"
    t.integer "orientation"
    t.string "platform"
    t.bigint "project_id", null: false
    t.datetime "recorded_at"
    t.string "resolution"
    t.integer "source", null: false
    t.bigint "tenant_id"
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_footages_on_game_id"
    t.index ["project_id"], name: "index_footages_on_project_id"
    t.index ["tenant_id", "local_path"], name: "index_footages_on_tenant_id_and_local_path", unique: true
    t.index ["tenant_id"], name: "index_footages_on_tenant_id"
  end

  create_table "games", force: :cascade do |t|
    t.bigint "collection_id"
    t.datetime "created_at", null: false
    t.jsonb "platforms", default: [], null: false
    t.string "publisher"
    t.bigint "tenant_id", null: false
    t.string "title", default: "Untitled game", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_games_on_collection_id"
    t.index ["tenant_id", "title"], name: "index_games_on_tenant_id_and_title"
    t.index ["tenant_id"], name: "index_games_on_tenant_id"
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

  create_table "notes", force: :cascade do |t|
    t.integer "chars_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1024
    t.datetime "last_modified_at", null: false
    t.string "path", null: false
    t.bigint "project_id", null: false
    t.bigint "tenant_id", null: false
    t.string "title", default: "Untitled note", null: false
    t.datetime "updated_at", null: false
    t.integer "words_count", default: 0, null: false
    t.index ["project_id"], name: "index_notes_on_project_id"
    t.index ["tenant_id", "path"], name: "index_notes_on_tenant_id_and_path", unique: true
    t.index ["tenant_id"], name: "index_notes_on_tenant_id"
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

  create_table "project_references", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "project_id", null: false
    t.bigint "referenceable_id", null: false
    t.string "referenceable_type", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["project_id", "referenceable_type", "referenceable_id"], name: "index_project_references_unique_per_project", unique: true
    t.index ["project_id"], name: "index_project_references_on_project_id"
    t.index ["referenceable_type", "referenceable_id"], name: "index_project_references_on_referenceable"
    t.index ["tenant_id"], name: "index_project_references_on_tenant_id"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", default: "Untitled project", null: false
    t.bigint "tenant_id", null: false
    t.datetime "updated_at", null: false
    t.index ["tenant_id", "name"], name: "index_projects_on_tenant_id_and_name"
    t.index ["tenant_id"], name: "index_projects_on_tenant_id"
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
    t.datetime "notes_syncing_at"
    t.datetime "updated_at", null: false
  end

  create_table "timelines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "export_filename"
    t.decimal "fps", precision: 6, scale: 3
    t.bigint "project_id", null: false
    t.string "resolution"
    t.integer "state", default: 0, null: false
    t.bigint "tenant_id", null: false
    t.string "title", default: "Untitled timeline", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id"
    t.index ["project_id"], name: "index_timelines_on_project_id"
    t.index ["state"], name: "index_timelines_on_state"
    t.index ["tenant_id"], name: "index_timelines_on_tenant_id"
    t.index ["video_id"], name: "index_timelines_on_video_id"
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

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "bulk_operation_items", "bulk_operations"
  add_foreign_key "bulk_operation_items", "videos"
  add_foreign_key "channels", "tenants"
  add_foreign_key "collections", "tenants"
  add_foreign_key "footages", "games"
  add_foreign_key "footages", "projects"
  add_foreign_key "footages", "tenants"
  add_foreign_key "games", "collections"
  add_foreign_key "games", "tenants"
  add_foreign_key "notes", "projects"
  add_foreign_key "notes", "tenants"
  add_foreign_key "playlist_items", "playlists"
  add_foreign_key "playlist_items", "videos"
  add_foreign_key "playlists", "channels"
  add_foreign_key "project_references", "projects"
  add_foreign_key "project_references", "tenants"
  add_foreign_key "projects", "tenants"
  add_foreign_key "timelines", "projects"
  add_foreign_key "timelines", "tenants"
  add_foreign_key "timelines", "videos"
  add_foreign_key "users", "tenants"
  add_foreign_key "video_stats", "videos"
  add_foreign_key "video_uploads", "channels"
  add_foreign_key "video_uploads", "videos"
  add_foreign_key "videos", "channels"
end
