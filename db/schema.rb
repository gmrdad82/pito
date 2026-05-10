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

ActiveRecord::Schema[8.1].define(version: 2026_05_10_021811) do
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

  create_table "api_tokens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at"
    t.string "last_token_preview", null: false
    t.datetime "last_used_at"
    t.string "name", null: false
    t.datetime "revoked_at"
    t.jsonb "scopes", default: [], null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["expires_at"], name: "index_api_tokens_on_expires_at"
    t.index ["token_digest"], name: "index_api_tokens_on_token_digest", unique: true
    t.index ["user_id"], name: "index_api_tokens_on_user_id"
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
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.bigint "oauth_identity_id"
    t.boolean "star", default: false, null: false
    t.datetime "updated_at", null: false
    t.index ["channel_url"], name: "index_channels_on_channel_url", unique: true
    t.index ["last_synced_at"], name: "index_channels_on_last_synced_at"
    t.index ["oauth_identity_id"], name: "index_channels_on_oauth_identity_id"
  end

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", default: "Untitled collection", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_collections_on_name"
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
    t.bigint "filesize_bytes"
    t.decimal "fps", precision: 6, scale: 3
    t.datetime "frames_extracted_at"
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
    t.datetime "updated_at", null: false
    t.index ["game_id"], name: "index_footages_on_game_id"
    t.index ["local_path"], name: "index_footages_on_local_path", unique: true
    t.index ["project_id"], name: "index_footages_on_project_id"
  end

  create_table "games", force: :cascade do |t|
    t.bigint "collection_id"
    t.datetime "created_at", null: false
    t.jsonb "platforms", default: [], null: false
    t.string "publisher"
    t.string "title", default: "Untitled game", null: false
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_games_on_collection_id"
    t.index ["title"], name: "index_games_on_title"
  end

  create_table "google_identities", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.datetime "expires_at", null: false
    t.string "google_subject_id", null: false
    t.datetime "last_authorized_at", null: false
    t.datetime "last_refreshed_at"
    t.boolean "needs_reauth", default: false, null: false
    t.text "refresh_token"
    t.jsonb "scopes", default: [], null: false
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["google_subject_id"], name: "index_google_identities_on_google_subject_id", unique: true
    t.index ["user_id"], name: "index_google_identities_on_user_id"
  end

  create_table "notes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.vector "embedding", limit: 1024
    t.datetime "last_modified_at", null: false
    t.string "path", null: false
    t.bigint "project_id", null: false
    t.string "title", default: "Untitled note", null: false
    t.datetime "updated_at", null: false
    t.integer "words_count", default: 0, null: false
    t.index ["project_id", "path"], name: "index_notes_on_project_id_and_path", unique: true
    t.index ["project_id"], name: "index_notes_on_project_id"
  end

  create_table "oauth_access_grants", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in", null: false
    t.text "redirect_uri", null: false
    t.bigint "resource_owner_id", null: false
    t.datetime "revoked_at"
    t.string "scopes", default: "", null: false
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_grants_on_application_id"
    t.index ["resource_owner_id"], name: "index_oauth_access_grants_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_grants_on_token", unique: true
  end

  create_table "oauth_access_tokens", force: :cascade do |t|
    t.bigint "application_id", null: false
    t.datetime "created_at", null: false
    t.integer "expires_in"
    t.string "previous_refresh_token", default: "", null: false
    t.string "refresh_token"
    t.bigint "resource_owner_id"
    t.datetime "revoked_at"
    t.string "scopes"
    t.string "token", null: false
    t.index ["application_id"], name: "index_oauth_access_tokens_on_application_id"
    t.index ["refresh_token"], name: "index_oauth_access_tokens_on_refresh_token", unique: true
    t.index ["resource_owner_id"], name: "index_oauth_access_tokens_on_resource_owner_id"
    t.index ["token"], name: "index_oauth_access_tokens_on_token", unique: true
  end

  create_table "oauth_applications", force: :cascade do |t|
    t.boolean "confidential", default: false, null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.text "redirect_uri", null: false
    t.string "scopes", default: "", null: false
    t.string "secret", null: false
    t.string "uid", null: false
    t.datetime "updated_at", null: false
    t.index ["uid"], name: "index_oauth_applications_on_uid", unique: true
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
    t.datetime "updated_at", null: false
    t.index ["project_id", "referenceable_type", "referenceable_id"], name: "index_project_references_unique_per_project", unique: true
    t.index ["project_id"], name: "index_project_references_on_project_id"
    t.index ["referenceable_type", "referenceable_id"], name: "index_project_references_on_referenceable"
  end

  create_table "projects", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "footage_duration_seconds", default: 0, null: false
    t.integer "footages_count", default: 0, null: false
    t.string "name", default: "Untitled project", null: false
    t.integer "notes_count", default: 0, null: false
    t.integer "notes_words_total", default: 0, null: false
    t.integer "timelines_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_projects_on_name"
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

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.inet "ip"
    t.datetime "last_activity_at"
    t.boolean "remember", default: false, null: false
    t.datetime "revoked_at"
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["token_digest"], name: "index_sessions_on_token_digest", unique: true
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "timelines", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "export_filename"
    t.decimal "fps", precision: 6, scale: 3
    t.bigint "project_id", null: false
    t.string "resolution"
    t.integer "state", default: 0, null: false
    t.string "title", default: "Untitled timeline", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id"
    t.index ["project_id"], name: "index_timelines_on_project_id"
    t.index ["state"], name: "index_timelines_on_state"
    t.index ["video_id"], name: "index_timelines_on_video_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.citext "email", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email"], name: "index_users_on_email", unique: true
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
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.bigint "oauth_identity_id"
    t.boolean "star", default: false, null: false
    t.datetime "updated_at", null: false
    t.string "youtube_video_id"
    t.index ["channel_id"], name: "index_videos_on_channel_id"
    t.index ["oauth_identity_id"], name: "index_videos_on_oauth_identity_id"
    t.index ["youtube_video_id"], name: "index_videos_on_youtube_video_id", unique: true
  end

  create_table "youtube_api_calls", force: :cascade do |t|
    t.string "client_kind", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "endpoint", null: false
    t.text "error_message"
    t.bigint "google_identity_id"
    t.string "http_method", null: false
    t.integer "http_status"
    t.string "outcome", null: false
    t.integer "units", null: false
    t.bigint "user_id"
    t.index ["client_kind", "created_at"], name: "index_youtube_api_calls_on_kind_time"
    t.index ["google_identity_id", "created_at"], name: "index_youtube_api_calls_on_identity_time"
    t.index ["google_identity_id"], name: "index_youtube_api_calls_on_google_identity_id"
    t.index ["outcome", "created_at"], name: "index_youtube_api_calls_on_outcome_time"
    t.index ["user_id"], name: "index_youtube_api_calls_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "bulk_operation_items", "bulk_operations"
  add_foreign_key "bulk_operation_items", "videos"
  add_foreign_key "channels", "google_identities", column: "oauth_identity_id"
  add_foreign_key "footages", "games"
  add_foreign_key "footages", "projects"
  add_foreign_key "games", "collections"
  add_foreign_key "google_identities", "users"
  add_foreign_key "notes", "projects"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "playlist_items", "playlists"
  add_foreign_key "playlist_items", "videos"
  add_foreign_key "playlists", "channels"
  add_foreign_key "project_references", "projects"
  add_foreign_key "sessions", "users"
  add_foreign_key "timelines", "projects"
  add_foreign_key "timelines", "videos"
  add_foreign_key "video_stats", "videos"
  add_foreign_key "video_uploads", "channels"
  add_foreign_key "video_uploads", "videos"
  add_foreign_key "videos", "channels"
  add_foreign_key "videos", "google_identities", column: "oauth_identity_id"
  add_foreign_key "youtube_api_calls", "google_identities"
  add_foreign_key "youtube_api_calls", "users"
end
