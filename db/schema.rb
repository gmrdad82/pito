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

ActiveRecord::Schema[8.1].define(version: 2026_05_10_140002) do
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
    t.string "timezone", default: "UTC", null: false
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

  create_table "calendar_entries", force: :cascade do |t|
    t.boolean "all_day", default: false, null: false
    t.bigint "channel_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.text "description"
    t.datetime "ends_at"
    t.integer "entry_type", null: false
    t.bigint "game_id"
    t.boolean "manual_date_override", default: false, null: false
    t.jsonb "metadata", default: {}, null: false
    t.bigint "milestone_rule_id"
    t.boolean "notify_anyway", default: false, null: false
    t.bigint "parent_entry_id"
    t.bigint "project_id"
    t.integer "release_precision"
    t.integer "source", default: 0, null: false
    t.jsonb "source_ref"
    t.datetime "starts_at", null: false
    t.integer "state", default: 0, null: false
    t.boolean "tba_remind_monthly", default: false, null: false
    t.string "timezone", default: "UTC", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id"
    t.index "entry_type, ((source_ref ->> 'channel_id'::text))", name: "index_calendar_entries_unique_channel_source_ref", unique: true, where: "((entry_type = 0) AND (source_ref IS NOT NULL))"
    t.index "entry_type, ((source_ref ->> 'game_id'::text))", name: "index_calendar_entries_unique_game_source_ref", unique: true, where: "((entry_type = 3) AND (source_ref IS NOT NULL))"
    t.index "entry_type, ((source_ref ->> 'video_id'::text))", name: "index_calendar_entries_unique_video_source_ref", unique: true, where: "((entry_type = ANY (ARRAY[1, 2])) AND (source_ref IS NOT NULL))"
    t.index ["channel_id"], name: "index_calendar_entries_on_channel_id", where: "(channel_id IS NOT NULL)"
    t.index ["created_by_user_id"], name: "index_calendar_entries_on_created_by_user_id", where: "(created_by_user_id IS NOT NULL)"
    t.index ["ends_at"], name: "index_calendar_entries_on_ends_at", where: "(ends_at IS NOT NULL)"
    t.index ["entry_type", "starts_at"], name: "index_calendar_entries_on_entry_type_and_starts_at"
    t.index ["entry_type"], name: "index_calendar_entries_on_entry_type"
    t.index ["game_id"], name: "index_calendar_entries_on_game_id", where: "(game_id IS NOT NULL)"
    t.index ["metadata"], name: "index_calendar_entries_on_metadata", using: :gin
    t.index ["milestone_rule_id"], name: "index_calendar_entries_on_milestone_rule_id", where: "(milestone_rule_id IS NOT NULL)"
    t.index ["parent_entry_id"], name: "index_calendar_entries_on_parent_entry_id", where: "(parent_entry_id IS NOT NULL)"
    t.index ["project_id"], name: "index_calendar_entries_on_project_id", where: "(project_id IS NOT NULL)"
    t.index ["source"], name: "index_calendar_entries_on_source"
    t.index ["source_ref"], name: "index_calendar_entries_on_source_ref", where: "(source_ref IS NOT NULL)", using: :gin
    t.index ["starts_at"], name: "index_calendar_entries_on_starts_at"
    t.index ["state", "starts_at"], name: "index_calendar_entries_on_state_and_starts_at"
    t.index ["state"], name: "index_calendar_entries_on_state"
    t.index ["video_id"], name: "index_calendar_entries_on_video_id", where: "(video_id IS NOT NULL)"
    t.check_constraint "ends_at IS NULL OR ends_at >= starts_at", name: "calendar_entries_ends_at_after_starts_at"
  end

  create_table "channels", force: :cascade do |t|
    t.string "channel_url", null: false
    t.datetime "created_at", null: false
    t.datetime "last_synced_at"
    t.boolean "star", default: false, null: false
    t.datetime "updated_at", null: false
    t.bigint "youtube_connection_id"
    t.index ["channel_url"], name: "index_channels_on_channel_url", unique: true
    t.index ["last_synced_at"], name: "index_channels_on_last_synced_at"
    t.index ["youtube_connection_id"], name: "index_channels_on_youtube_connection_id"
  end

  create_table "collections", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "name", default: "Untitled collection", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_collections_on_name"
  end

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "igdb_id", null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["igdb_id"], name: "index_companies_on_igdb_id", unique: true
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

  create_table "game_developers", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_game_developers_on_company_id"
    t.index ["game_id", "company_id"], name: "index_game_developers_on_game_id_and_company_id", unique: true
    t.index ["game_id"], name: "index_game_developers_on_game_id"
  end

  create_table "game_genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.bigint "genre_id", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "genre_id"], name: "index_game_genres_on_game_id_and_genre_id", unique: true
    t.index ["game_id"], name: "index_game_genres_on_game_id"
    t.index ["genre_id"], name: "index_game_genres_on_genre_id"
  end

  create_table "game_platforms", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.bigint "platform_id", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "platform_id"], name: "index_game_platforms_on_game_id_and_platform_id", unique: true
    t.index ["game_id"], name: "index_game_platforms_on_game_id"
    t.index ["platform_id"], name: "index_game_platforms_on_platform_id"
  end

  create_table "game_publishers", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_game_publishers_on_company_id"
    t.index ["game_id", "company_id"], name: "index_game_publishers_on_game_id_and_company_id", unique: true
    t.index ["game_id"], name: "index_game_publishers_on_game_id"
  end

  create_table "games", force: :cascade do |t|
    t.decimal "aggregated_rating", precision: 5, scale: 2
    t.integer "aggregated_rating_count"
    t.bigint "collection_id"
    t.string "cover_image_id"
    t.datetime "created_at", null: false
    t.string "external_epic_id"
    t.string "external_gog_id"
    t.string "external_steam_app_id"
    t.integer "hours_of_footage_cached"
    t.integer "hours_of_footage_manual"
    t.string "igdb_checksum"
    t.bigint "igdb_id"
    t.decimal "igdb_rating", precision: 5, scale: 2
    t.integer "igdb_rating_count"
    t.string "igdb_slug"
    t.datetime "igdb_synced_at"
    t.text "last_sync_error"
    t.boolean "manual_date_override", default: false, null: false
    t.text "notes"
    t.bigint "platform_owned_id"
    t.jsonb "platforms", default: [], null: false
    t.date "played_at"
    t.string "publisher"
    t.date "release_date"
    t.integer "release_year"
    t.text "summary"
    t.string "title", default: "Untitled game", null: false
    t.decimal "total_rating", precision: 5, scale: 2
    t.integer "total_rating_count"
    t.integer "ttb_completionist_seconds"
    t.integer "ttb_extras_seconds"
    t.integer "ttb_main_seconds"
    t.datetime "updated_at", null: false
    t.index ["collection_id"], name: "index_games_on_collection_id"
    t.index ["external_steam_app_id"], name: "index_games_on_external_steam_app_id", where: "(external_steam_app_id IS NOT NULL)"
    t.index ["igdb_id"], name: "index_games_on_igdb_id", unique: true, where: "(igdb_id IS NOT NULL)"
    t.index ["igdb_slug"], name: "index_games_on_igdb_slug", unique: true, where: "(igdb_slug IS NOT NULL)"
    t.index ["igdb_synced_at"], name: "index_games_on_igdb_synced_at"
    t.index ["platform_owned_id"], name: "index_games_on_platform_owned_id"
    t.index ["release_year"], name: "index_games_on_release_year"
    t.index ["title"], name: "index_games_on_title"
  end

  create_table "genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "igdb_id", null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["igdb_id"], name: "index_genres_on_igdb_id", unique: true
  end

  create_table "milestone_rules", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.integer "direction", default: 0, null: false
    t.boolean "enabled", default: true, null: false
    t.datetime "fired_at"
    t.string "metric", null: false
    t.integer "metric_window", default: 0, null: false
    t.string "name", null: false
    t.bigint "scope_id"
    t.integer "scope_type", null: false
    t.decimal "threshold", precision: 20, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_milestone_rules_on_created_by_user_id", where: "(created_by_user_id IS NOT NULL)"
    t.index ["enabled"], name: "index_milestone_rules_on_enabled"
    t.index ["fired_at"], name: "index_milestone_rules_on_fired_at"
    t.index ["metric"], name: "index_milestone_rules_on_metric"
    t.index ["scope_id"], name: "index_milestone_rules_on_scope_id", where: "(scope_id IS NOT NULL)"
    t.index ["scope_type"], name: "index_milestone_rules_on_scope_type"
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

  create_table "platforms", force: :cascade do |t|
    t.string "abbreviation"
    t.datetime "created_at", null: false
    t.bigint "igdb_id", null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["igdb_id"], name: "index_platforms_on_igdb_id", unique: true
  end

  create_table "playlist_videos", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "playlist_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.string "youtube_playlist_item_id", null: false
    t.index ["playlist_id", "position"], name: "index_playlist_videos_on_playlist_id_and_position"
    t.index ["playlist_id", "video_id"], name: "index_playlist_videos_on_playlist_id_and_video_id", unique: true
    t.index ["playlist_id"], name: "index_playlist_videos_on_playlist_id"
    t.index ["video_id"], name: "index_playlist_videos_on_video_id"
    t.index ["youtube_playlist_item_id"], name: "index_playlist_videos_on_youtube_playlist_item_id", unique: true
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
    t.string "category_id"
    t.bigint "channel_id", null: false
    t.boolean "contains_synthetic_media", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.string "etag"
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.boolean "made_for_kids_effective", default: false, null: false
    t.boolean "pre_publish_age_ok", default: false, null: false
    t.datetime "pre_publish_checked_at"
    t.boolean "pre_publish_end_screen_ok", default: false, null: false
    t.boolean "pre_publish_game_ok", default: false, null: false
    t.boolean "pre_publish_paid_promotion_ok", default: false, null: false
    t.integer "privacy_status", default: 0, null: false
    t.bigint "project_id"
    t.datetime "publish_at"
    t.datetime "published_at"
    t.boolean "self_declared_made_for_kids", default: false, null: false
    t.boolean "star", default: false, null: false
    t.jsonb "tags", default: [], null: false
    t.string "thumbnail_url"
    t.string "title", limit: 100, default: "", null: false
    t.datetime "updated_at", null: false
    t.bigint "youtube_connection_id"
    t.string "youtube_video_id"
    t.index ["channel_id"], name: "index_videos_on_channel_id"
    t.index ["privacy_status"], name: "index_videos_on_privacy_status"
    t.index ["project_id"], name: "index_videos_on_project_id"
    t.index ["publish_at"], name: "index_videos_on_publish_at", where: "(publish_at IS NOT NULL)"
    t.index ["published_at"], name: "index_videos_on_published_at"
    t.index ["tags"], name: "index_videos_on_tags", using: :gin
    t.index ["youtube_connection_id"], name: "index_videos_on_youtube_connection_id"
    t.index ["youtube_video_id"], name: "index_videos_on_youtube_video_id", unique: true
  end

  create_table "youtube_api_calls", force: :cascade do |t|
    t.string "client_kind", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.string "endpoint", null: false
    t.text "error_message"
    t.string "http_method", null: false
    t.integer "http_status"
    t.string "outcome", null: false
    t.integer "units", null: false
    t.bigint "user_id"
    t.bigint "youtube_connection_id"
    t.index ["client_kind", "created_at"], name: "index_youtube_api_calls_on_kind_time"
    t.index ["outcome", "created_at"], name: "index_youtube_api_calls_on_outcome_time"
    t.index ["user_id"], name: "index_youtube_api_calls_on_user_id"
    t.index ["youtube_connection_id", "created_at"], name: "index_youtube_api_calls_on_connection_time"
    t.index ["youtube_connection_id"], name: "index_youtube_api_calls_on_youtube_connection_id"
  end

  create_table "youtube_connections", force: :cascade do |t|
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
    t.index ["google_subject_id"], name: "index_youtube_connections_on_google_subject_id", unique: true
    t.index ["user_id"], name: "index_youtube_connections_on_user_id"
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "api_tokens", "users"
  add_foreign_key "bulk_operation_items", "bulk_operations"
  add_foreign_key "bulk_operation_items", "videos"
  add_foreign_key "calendar_entries", "calendar_entries", column: "parent_entry_id", on_delete: :nullify
  add_foreign_key "calendar_entries", "channels", on_delete: :cascade
  add_foreign_key "calendar_entries", "games", on_delete: :cascade
  add_foreign_key "calendar_entries", "milestone_rules", on_delete: :nullify
  add_foreign_key "calendar_entries", "projects", on_delete: :nullify
  add_foreign_key "calendar_entries", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "calendar_entries", "videos", on_delete: :cascade
  add_foreign_key "channels", "youtube_connections"
  add_foreign_key "footages", "games"
  add_foreign_key "footages", "projects"
  add_foreign_key "game_developers", "companies", on_delete: :cascade
  add_foreign_key "game_developers", "games", on_delete: :cascade
  add_foreign_key "game_genres", "games", on_delete: :cascade
  add_foreign_key "game_genres", "genres", on_delete: :cascade
  add_foreign_key "game_platforms", "games", on_delete: :cascade
  add_foreign_key "game_platforms", "platforms", on_delete: :cascade
  add_foreign_key "game_publishers", "companies", on_delete: :cascade
  add_foreign_key "game_publishers", "games", on_delete: :cascade
  add_foreign_key "games", "collections"
  add_foreign_key "games", "platforms", column: "platform_owned_id", on_delete: :nullify
  add_foreign_key "milestone_rules", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "notes", "projects"
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "playlist_videos", "playlists"
  add_foreign_key "playlist_videos", "videos"
  add_foreign_key "playlists", "channels"
  add_foreign_key "project_references", "projects"
  add_foreign_key "sessions", "users"
  add_foreign_key "timelines", "projects"
  add_foreign_key "timelines", "videos"
  add_foreign_key "video_stats", "videos"
  add_foreign_key "video_uploads", "channels"
  add_foreign_key "video_uploads", "videos"
  add_foreign_key "videos", "channels"
  add_foreign_key "videos", "projects", on_delete: :nullify
  add_foreign_key "videos", "youtube_connections"
  add_foreign_key "youtube_api_calls", "users"
  add_foreign_key "youtube_api_calls", "youtube_connections"
  add_foreign_key "youtube_connections", "users"
end
