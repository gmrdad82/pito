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

ActiveRecord::Schema[8.1].define(version: 2026_05_16_232156) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pgcrypto"
  enable_extension "vector"

  # Custom types defined in this database.
  # Note that some types may not work with other database engines. Be careful if changing database.
  create_enum "analytics_window", ["7d", "28d", "90d", "lifetime"]

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
    t.boolean "reindex_running", default: false, null: false
    t.datetime "reindex_started_at"
    t.datetime "updated_at", null: false
    t.text "value"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "auth_audit_logs", force: :cascade do |t|
    t.bigint "acting_user_id", null: false
    t.integer "action", null: false
    t.datetime "created_at", null: false
    t.jsonb "metadata", default: {}, null: false
    t.integer "source_surface", null: false
    t.bigint "target_id", null: false
    t.string "target_type", null: false
    t.datetime "updated_at", null: false
    t.index ["acting_user_id"], name: "index_auth_audit_logs_on_acting_user_id"
    t.index ["action"], name: "index_auth_audit_logs_on_action"
    t.index ["created_at"], name: "index_auth_audit_logs_on_created_at"
    t.index ["source_surface"], name: "index_auth_audit_logs_on_source_surface"
    t.index ["target_type", "target_id"], name: "index_auth_audit_logs_on_target_type_and_target_id"
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

  create_table "bundle_members", force: :cascade do |t|
    t.bigint "bundle_id", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.integer "position", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_id", "game_id"], name: "index_bundle_members_on_bundle_and_game", unique: true
    t.index ["bundle_id", "position"], name: "index_bundle_members_on_bundle_and_position"
    t.index ["bundle_id"], name: "index_bundle_members_on_bundle_id"
    t.index ["game_id"], name: "index_bundle_members_on_game_id"
  end

  create_table "bundles", force: :cascade do |t|
    t.integer "bundle_type", default: 0, null: false
    t.string "composite_cover_checksum"
    t.string "composite_cover_path"
    t.datetime "created_at", null: false
    t.bigint "igdb_source_id"
    t.integer "igdb_source_type"
    t.text "last_error"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["bundle_type"], name: "index_bundles_on_bundle_type"
    t.index ["igdb_source_id"], name: "index_bundles_on_igdb_source_id", where: "(igdb_source_id IS NOT NULL)"
    t.index ["igdb_source_type", "igdb_source_id"], name: "index_bundles_on_igdb_source_pair", unique: true, where: "((igdb_source_type IS NOT NULL) AND (igdb_source_id IS NOT NULL))"
    t.index ["slug"], name: "index_bundles_on_slug", unique: true
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
    t.index ["milestone_rule_id"], name: "index_calendar_entries_unique_milestone_rule", unique: true, where: "((entry_type = 6) AND (source = 2))"
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

  create_table "channel_change_logs", force: :cascade do |t|
    t.datetime "changed_at", null: false
    t.bigint "changed_by_user_id", null: false
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.string "field", null: false
    t.string "new_value", null: false
    t.string "old_value"
    t.datetime "updated_at", null: false
    t.index ["changed_at"], name: "index_channel_change_logs_on_changed_at"
    t.index ["changed_by_user_id"], name: "index_channel_change_logs_on_changed_by_user_id"
    t.index ["channel_id"], name: "index_channel_change_logs_on_channel_id"
  end

  create_table "channel_dailies", force: :cascade do |t|
    t.bigint "ad_impressions"
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.bigint "card_clicks", default: 0, null: false
    t.bigint "card_impressions", default: 0, null: false
    t.bigint "card_teaser_clicks", default: 0, null: false
    t.bigint "card_teaser_impressions", default: 0, null: false
    t.bigint "channel_id", null: false
    t.bigint "comments", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "dislikes", default: 0, null: false
    t.bigint "engaged_views", default: 0, null: false
    t.decimal "estimated_ad_revenue", precision: 12, scale: 4
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.bigint "estimated_red_minutes_watched", default: 0, null: false
    t.decimal "estimated_red_partner_revenue", precision: 12, scale: 4
    t.decimal "estimated_revenue", precision: 12, scale: 4
    t.decimal "gross_revenue", precision: 12, scale: 4
    t.bigint "likes", default: 0, null: false
    t.bigint "monetized_playbacks"
    t.bigint "red_views", default: 0, null: false
    t.bigint "shares", default: 0, null: false
    t.bigint "subscribers_gained", default: 0, null: false
    t.bigint "subscribers_lost", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_thumbnail_impressions", default: 0, null: false
    t.bigint "videos_added_to_playlists", default: 0, null: false
    t.bigint "videos_removed_from_playlists", default: 0, null: false
    t.bigint "views", default: 0, null: false
    t.index ["channel_id", "date"], name: "index_channel_dailies_on_channel_id_and_date", unique: true
    t.index ["channel_id"], name: "index_channel_dailies_on_channel_id"
    t.index ["date"], name: "index_channel_dailies_on_date"
  end

  create_table "channel_window_summaries", force: :cascade do |t|
    t.bigint "ad_impressions"
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.decimal "average_view_percentage", precision: 10, scale: 6
    t.decimal "card_click_rate", precision: 10, scale: 6
    t.bigint "card_clicks", default: 0, null: false
    t.bigint "card_impressions", default: 0, null: false
    t.decimal "card_teaser_click_rate", precision: 10, scale: 6
    t.bigint "card_teaser_clicks", default: 0, null: false
    t.bigint "card_teaser_impressions", default: 0, null: false
    t.bigint "channel_id", null: false
    t.bigint "comments", default: 0, null: false
    t.decimal "cpm", precision: 12, scale: 4
    t.datetime "created_at", null: false
    t.bigint "dislikes", default: 0, null: false
    t.bigint "engaged_views", default: 0, null: false
    t.decimal "estimated_ad_revenue", precision: 12, scale: 4
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.bigint "estimated_red_minutes_watched", default: 0, null: false
    t.decimal "estimated_red_partner_revenue", precision: 12, scale: 4
    t.decimal "estimated_revenue", precision: 12, scale: 4
    t.decimal "gross_revenue", precision: 12, scale: 4
    t.bigint "likes", default: 0, null: false
    t.bigint "monetized_playbacks"
    t.decimal "playback_based_cpm", precision: 12, scale: 4
    t.bigint "red_views", default: 0, null: false
    t.bigint "shares", default: 0, null: false
    t.bigint "subscribers_gained", default: 0, null: false
    t.bigint "subscribers_lost", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_thumbnail_impressions", default: 0, null: false
    t.decimal "video_thumbnail_impressions_click_rate", precision: 10, scale: 6
    t.bigint "videos_added_to_playlists", default: 0, null: false
    t.bigint "videos_removed_from_playlists", default: 0, null: false
    t.bigint "views", default: 0, null: false
    t.enum "window", null: false, enum_type: "analytics_window"
    t.date "window_end", null: false
    t.date "window_start", null: false
    t.index ["channel_id", "window"], name: "idx_channel_window_summary_uniq", unique: true
    t.index ["channel_id"], name: "index_channel_window_summaries_on_channel_id"
  end

  create_table "channels", force: :cascade do |t|
    t.string "avatar_url"
    t.string "banner_url"
    t.string "channel_url", null: false
    t.string "country", limit: 2
    t.datetime "created_at", null: false
    t.string "default_language", limit: 10
    t.text "description"
    t.string "handle"
    t.datetime "handle_changed_at"
    t.boolean "hidden_subscriber_count", default: false, null: false
    t.text "keywords"
    t.datetime "last_synced_at"
    t.jsonb "links", default: [], null: false
    t.datetime "published_at"
    t.boolean "star", default: false, null: false
    t.bigint "subscriber_count"
    t.string "title"
    t.datetime "title_changed_at"
    t.datetime "updated_at", null: false
    t.integer "video_count"
    t.bigint "view_count"
    t.integer "watermark_offset_ms"
    t.string "watermark_timing"
    t.string "watermark_url"
    t.bigint "youtube_connection_id"
    t.index ["channel_url"], name: "index_channels_on_channel_url", unique: true
    t.index ["handle"], name: "index_channels_on_handle", where: "(handle IS NOT NULL)"
    t.index ["last_synced_at"], name: "index_channels_on_last_synced_at"
    t.index ["youtube_connection_id"], name: "index_channels_on_youtube_connection_id"
  end

  create_table "collections", force: :cascade do |t|
    t.string "composite_cover_checksum"
    t.string "composite_cover_path"
    t.datetime "created_at", null: false
    t.string "name", default: "Untitled collection", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_collections_on_name"
    t.index ["slug"], name: "index_collections_on_slug", unique: true
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

  create_table "friendly_id_slugs", force: :cascade do |t|
    t.datetime "created_at"
    t.string "scope"
    t.string "slug", null: false
    t.integer "sluggable_id", null: false
    t.string "sluggable_type", limit: 50
    t.index ["slug", "sluggable_type", "scope"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type_and_scope", unique: true
    t.index ["slug", "sluggable_type"], name: "index_friendly_id_slugs_on_slug_and_sluggable_type"
    t.index ["sluggable_type", "sluggable_id"], name: "index_friendly_id_slugs_on_sluggable_type_and_sluggable_id"
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

  create_table "game_platform_ownerships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.bigint "platform_id", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "platform_id"], name: "index_game_platform_ownerships_uniqueness", unique: true
    t.index ["game_id"], name: "index_game_platform_ownerships_on_game_id"
    t.index ["platform_id"], name: "index_game_platform_ownerships_on_platform_id"
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
    t.jsonb "platforms", default: [], null: false
    t.date "played_at"
    t.bigint "primary_genre_id"
    t.string "publisher"
    t.date "release_date"
    t.integer "release_year"
    t.boolean "resyncing", default: false, null: false
    t.text "summary"
    t.string "title", default: "Untitled game", null: false
    t.decimal "total_rating", precision: 5, scale: 2
    t.integer "total_rating_count"
    t.integer "ttb_completionist_seconds"
    t.integer "ttb_extras_seconds"
    t.integer "ttb_main_seconds"
    t.datetime "updated_at", null: false
    t.bigint "version_parent_id"
    t.string "version_title"
    t.index ["collection_id"], name: "index_games_on_collection_id"
    t.index ["external_steam_app_id"], name: "index_games_on_external_steam_app_id", where: "(external_steam_app_id IS NOT NULL)"
    t.index ["igdb_id"], name: "index_games_on_igdb_id", unique: true, where: "(igdb_id IS NOT NULL)"
    t.index ["igdb_slug"], name: "index_games_on_igdb_slug", unique: true, where: "(igdb_slug IS NOT NULL)"
    t.index ["igdb_synced_at"], name: "index_games_on_igdb_synced_at"
    t.index ["primary_genre_id"], name: "index_games_on_primary_genre_id"
    t.index ["release_year"], name: "index_games_on_release_year"
    t.index ["title"], name: "index_games_on_title"
    t.index ["version_parent_id"], name: "index_games_on_version_parent_id"
  end

  create_table "genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "igdb_id", null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["igdb_id"], name: "index_genres_on_igdb_id", unique: true
  end

  create_table "import_jobs", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "enqueued_by_id", null: false
    t.jsonb "error_payload"
    t.integer "failed_videos", default: 0, null: false
    t.integer "imported_videos", default: 0, null: false
    t.datetime "started_at"
    t.integer "status", default: 0, null: false
    t.integer "total_videos", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["channel_id", "status"], name: "index_import_jobs_on_channel_id_and_status"
    t.index ["channel_id"], name: "index_import_jobs_on_channel_id"
    t.index ["enqueued_by_id"], name: "index_import_jobs_on_enqueued_by_id"
    t.index ["status", "created_at"], name: "index_import_jobs_on_status_and_created_at"
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
    t.string "slug", null: false
    t.decimal "threshold", precision: 20, scale: 4, null: false
    t.datetime "updated_at", null: false
    t.index ["created_by_user_id"], name: "index_milestone_rules_on_created_by_user_id", where: "(created_by_user_id IS NOT NULL)"
    t.index ["enabled"], name: "index_milestone_rules_on_enabled"
    t.index ["fired_at"], name: "index_milestone_rules_on_fired_at"
    t.index ["metric"], name: "index_milestone_rules_on_metric"
    t.index ["scope_id"], name: "index_milestone_rules_on_scope_id", where: "(scope_id IS NOT NULL)"
    t.index ["scope_type"], name: "index_milestone_rules_on_scope_type"
    t.index ["slug"], name: "index_milestone_rules_on_slug", unique: true
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

  create_table "notification_delivery_channels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.boolean "daily_digest", default: false, null: false
    t.boolean "everything", default: false, null: false
    t.string "kind", null: false
    t.datetime "last_validated_at"
    t.datetime "updated_at", null: false
    t.text "webhook_url"
    t.index ["kind"], name: "index_notification_delivery_channels_on_kind", unique: true
  end

  create_table "notifications", force: :cascade do |t|
    t.text "body"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.string "dedup_key"
    t.datetime "discord_delivered_at"
    t.jsonb "event_payload", default: {}, null: false
    t.string "event_type", null: false
    t.datetime "fires_at", null: false
    t.datetime "in_app_read_at"
    t.integer "kind", null: false
    t.text "last_error"
    t.integer "retry_count", default: 0, null: false
    t.integer "severity", default: 0, null: false
    t.datetime "slack_delivered_at"
    t.bigint "source_calendar_entry_id"
    t.bigint "source_milestone_rule_id"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.string "url"
    t.index ["created_at"], name: "index_notifications_on_created_at"
    t.index ["created_by_user_id"], name: "index_notifications_on_created_by_user_id", where: "(created_by_user_id IS NOT NULL)"
    t.index ["event_type", "dedup_key"], name: "index_notifications_unique_dedup", unique: true, where: "(dedup_key IS NOT NULL)"
    t.index ["event_type", "source_calendar_entry_id", "fires_at"], name: "index_notifications_unique_calendar_event", unique: true, where: "(source_calendar_entry_id IS NOT NULL)"
    t.index ["event_type"], name: "index_notifications_on_event_type"
    t.index ["fires_at"], name: "index_notifications_on_fires_at"
    t.index ["in_app_read_at", "created_at"], name: "index_notifications_on_read_state_and_recency"
    t.index ["in_app_read_at"], name: "index_notifications_on_unread", where: "(in_app_read_at IS NULL)"
    t.index ["kind"], name: "index_notifications_on_kind"
    t.index ["severity"], name: "index_notifications_on_severity"
    t.index ["source_calendar_entry_id"], name: "index_notifications_on_source_calendar_entry_id", where: "(source_calendar_entry_id IS NOT NULL)"
    t.index ["source_milestone_rule_id"], name: "index_notifications_on_source_milestone_rule_id", where: "(source_milestone_rule_id IS NOT NULL)"
    t.check_constraint "source_calendar_entry_id IS NOT NULL OR dedup_key IS NOT NULL", name: "notifications_idempotency_keys_present"
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
    t.bigint "igdb_id"
    t.string "name", null: false
    t.string "slug", null: false
    t.datetime "updated_at", null: false
    t.index ["igdb_id"], name: "index_platforms_on_igdb_id", unique: true
    t.index ["slug"], name: "index_platforms_on_slug", unique: true
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
    t.string "slug", null: false
    t.integer "timelines_count", default: 0, null: false
    t.datetime "updated_at", null: false
    t.index ["name"], name: "index_projects_on_name"
    t.index ["slug"], name: "index_projects_on_slug", unique: true
  end

  create_table "rejected_video_imports", force: :cascade do |t|
    t.bigint "channel_id", null: false
    t.datetime "created_at", null: false
    t.datetime "rejected_at", null: false
    t.bigint "rejected_by_id", null: false
    t.datetime "updated_at", null: false
    t.string "youtube_video_id", null: false
    t.index ["channel_id", "youtube_video_id"], name: "index_rejected_video_imports_unique", unique: true
    t.index ["channel_id"], name: "index_rejected_video_imports_on_channel_id"
    t.index ["rejected_by_id"], name: "index_rejected_video_imports_on_rejected_by_id"
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
    t.datetime "revoked_at"
    t.integer "state", default: 0, null: false
    t.string "token_digest", null: false
    t.datetime "updated_at", null: false
    t.text "user_agent"
    t.bigint "user_id", null: false
    t.index ["state"], name: "index_sessions_on_state"
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

  create_table "top_videos_windows", force: :cascade do |t|
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.decimal "average_view_percentage", precision: 10, scale: 6
    t.bigint "channel_id", null: false
    t.bigint "comments", default: 0, null: false
    t.datetime "created_at", null: false
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.bigint "likes", default: 0, null: false
    t.integer "rank", null: false
    t.bigint "subscribers_gained", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "views", default: 0, null: false
    t.enum "window", null: false, enum_type: "analytics_window"
    t.index ["channel_id", "window", "rank"], name: "idx_top_videos_window_rank_uniq", unique: true
    t.index ["channel_id", "window", "video_id"], name: "idx_top_videos_window_video_uniq", unique: true
    t.index ["channel_id"], name: "index_top_videos_windows_on_channel_id"
    t.index ["video_id"], name: "index_top_videos_windows_on_video_id"
  end

  create_table "totp_backup_codes", force: :cascade do |t|
    t.string "code_digest", null: false
    t.datetime "created_at", null: false
    t.datetime "updated_at", null: false
    t.datetime "used_at"
    t.bigint "user_id", null: false
    t.index ["used_at"], name: "index_totp_backup_codes_on_used_at"
    t.index ["user_id"], name: "index_totp_backup_codes_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_digest_run_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.string "password_digest", null: false
    t.string "time_zone", default: "Etc/UTC", null: false
    t.datetime "totp_disabled_at"
    t.datetime "totp_enabled_at"
    t.bigint "totp_last_used_step"
    t.text "totp_seed_encrypted"
    t.datetime "updated_at", null: false
    t.citext "username", null: false
    t.index ["last_digest_run_at"], name: "index_users_on_last_digest_run_at"
    t.index ["username"], name: "index_users_on_username", unique: true
  end

  create_table "video_change_logs", force: :cascade do |t|
    t.datetime "changed_at", null: false
    t.bigint "changed_by_user_id"
    t.datetime "created_at", null: false
    t.string "field", null: false
    t.text "new_value"
    t.text "old_value"
    t.integer "source", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["changed_at"], name: "index_video_change_logs_on_changed_at"
    t.index ["changed_by_user_id"], name: "index_video_change_logs_on_changed_by_user_id"
    t.index ["video_id"], name: "index_video_change_logs_on_video_id"
  end

  create_table "video_chapters", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "label", limit: 100, null: false
    t.integer "position", default: 0, null: false
    t.integer "start_seconds", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["video_id", "start_seconds"], name: "index_video_chapters_on_video_id_and_start_seconds", unique: true
    t.index ["video_id"], name: "index_video_chapters_on_video_id"
  end

  create_table "video_dailies", force: :cascade do |t|
    t.bigint "ad_impressions"
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.bigint "card_clicks", default: 0, null: false
    t.bigint "card_impressions", default: 0, null: false
    t.bigint "card_teaser_clicks", default: 0, null: false
    t.bigint "card_teaser_impressions", default: 0, null: false
    t.bigint "comments", default: 0, null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "dislikes", default: 0, null: false
    t.bigint "engaged_views", default: 0, null: false
    t.decimal "estimated_ad_revenue", precision: 12, scale: 4
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.bigint "estimated_red_minutes_watched", default: 0, null: false
    t.decimal "estimated_red_partner_revenue", precision: 12, scale: 4
    t.decimal "estimated_revenue", precision: 12, scale: 4
    t.decimal "gross_revenue", precision: 12, scale: 4
    t.bigint "likes", default: 0, null: false
    t.bigint "monetized_playbacks"
    t.bigint "red_views", default: 0, null: false
    t.bigint "shares", default: 0, null: false
    t.bigint "subscribers_gained", default: 0, null: false
    t.bigint "subscribers_lost", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "video_thumbnail_impressions", default: 0, null: false
    t.bigint "videos_added_to_playlists", default: 0, null: false
    t.bigint "videos_removed_from_playlists", default: 0, null: false
    t.bigint "views", default: 0, null: false
    t.index ["date"], name: "index_video_dailies_on_date"
    t.index ["video_id", "date"], name: "index_video_dailies_on_video_id_and_date", unique: true
    t.index ["video_id"], name: "index_video_dailies_on_video_id"
  end

  create_table "video_daily_by_age_group_genders", force: :cascade do |t|
    t.text "age_group", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "gender", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.decimal "viewer_percentage", precision: 10, scale: 6, default: "0.0", null: false
    t.index ["video_id", "date", "age_group", "gender"], name: "idx_video_daily_by_age_gender_uniq", unique: true
    t.index ["video_id"], name: "index_video_daily_by_age_group_genders_on_video_id"
  end

  create_table "video_daily_by_countries", force: :cascade do |t|
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.decimal "average_view_percentage", precision: 10, scale: 6
    t.text "country_code", null: false
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "views", default: 0, null: false
    t.index ["country_code"], name: "index_video_daily_by_countries_on_country_code"
    t.index ["video_id", "date", "country_code"], name: "idx_video_daily_by_country_uniq", unique: true
    t.index ["video_id"], name: "index_video_daily_by_countries_on_video_id"
  end

  create_table "video_daily_by_device_types", force: :cascade do |t|
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.decimal "average_view_percentage", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.text "device_type", null: false
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "views", default: 0, null: false
    t.index ["video_id", "date", "device_type"], name: "idx_video_daily_by_device_type_uniq", unique: true
    t.index ["video_id"], name: "index_video_daily_by_device_types_on_video_id"
  end

  create_table "video_daily_by_operating_systems", force: :cascade do |t|
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.decimal "average_view_percentage", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.text "operating_system", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "views", default: 0, null: false
    t.index ["video_id", "date", "operating_system"], name: "idx_video_daily_by_os_uniq", unique: true
    t.index ["video_id"], name: "index_video_daily_by_operating_systems_on_video_id"
  end

  create_table "video_daily_by_subscribed_statuses", force: :cascade do |t|
    t.decimal "average_view_percentage", precision: 10, scale: 6
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.text "subscribed_status", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "views", default: 0, null: false
    t.index ["video_id", "date", "subscribed_status"], name: "idx_video_daily_by_subscribed_status_uniq", unique: true
    t.index ["video_id"], name: "index_video_daily_by_subscribed_statuses_on_video_id"
  end

  create_table "video_daily_by_traffic_sources", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.date "date", null: false
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.text "traffic_source_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "video_thumbnail_impressions", default: 0, null: false
    t.decimal "video_thumbnail_impressions_click_rate", precision: 10, scale: 6
    t.bigint "views", default: 0, null: false
    t.index ["video_id", "date", "traffic_source_type"], name: "idx_video_daily_by_traffic_source_uniq", unique: true
    t.index ["video_id"], name: "index_video_daily_by_traffic_sources_on_video_id"
  end

  create_table "video_diffs", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "detected_at", null: false
    t.jsonb "payload", default: {}, null: false
    t.jsonb "resolution_payload"
    t.datetime "resolved_at"
    t.bigint "resolved_by_user_id"
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["resolved_at"], name: "index_video_diffs_on_resolved_at"
    t.index ["resolved_by_user_id"], name: "index_video_diffs_on_resolved_by_user_id"
    t.index ["video_id"], name: "index_video_diffs_on_video_id"
    t.index ["video_id"], name: "index_video_diffs_open_per_video", unique: true, where: "(resolved_at IS NULL)"
  end

  create_table "video_end_screens", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "kind", default: 0, null: false
    t.integer "position", default: 0, null: false
    t.string "target_id"
    t.string "target_label", limit: 100
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["video_id", "position"], name: "index_video_end_screens_on_video_id_and_position"
    t.index ["video_id"], name: "index_video_end_screens_on_video_id"
  end

  create_table "video_game_links", force: :cascade do |t|
    t.bigint "bundle_id"
    t.datetime "created_at", null: false
    t.bigint "created_by_user_id"
    t.bigint "game_id"
    t.boolean "is_primary", default: false, null: false
    t.integer "link_type", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["bundle_id"], name: "index_video_game_links_on_bundle_id"
    t.index ["created_by_user_id"], name: "index_video_game_links_on_created_by_user_id"
    t.index ["game_id"], name: "index_video_game_links_on_game_id"
    t.index ["is_primary"], name: "idx_video_game_links_primary", where: "(is_primary = true)"
    t.index ["link_type"], name: "index_video_game_links_on_link_type"
    t.index ["video_id", "bundle_id"], name: "idx_video_game_links_unique_bundle", unique: true, where: "(bundle_id IS NOT NULL)"
    t.index ["video_id", "game_id"], name: "idx_video_game_links_unique_game", unique: true, where: "(game_id IS NOT NULL)"
    t.index ["video_id"], name: "index_video_game_links_on_video_id"
    t.check_constraint "link_type = 0 AND game_id IS NOT NULL AND bundle_id IS NULL OR link_type = 1 AND bundle_id IS NOT NULL AND game_id IS NULL", name: "video_game_links_exactly_one_target"
  end

  create_table "video_retentions", force: :cascade do |t|
    t.decimal "audience_watch_ratio", precision: 10, scale: 6
    t.timestamptz "computed_at", default: -> { "CURRENT_TIMESTAMP" }, null: false
    t.decimal "elapsed_ratio_bucket", precision: 5, scale: 4, null: false
    t.decimal "relative_retention_performance", precision: 10, scale: 6
    t.bigint "started_watching", default: 0, null: false
    t.bigint "stopped_watching", default: 0, null: false
    t.bigint "total_segment_impressions", default: 0, null: false
    t.bigint "video_id", null: false
    t.index ["video_id", "elapsed_ratio_bucket"], name: "idx_video_retention_bucket_uniq", unique: true
    t.index ["video_id"], name: "index_video_retentions_on_video_id"
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

  create_table "video_viewer_time_buckets", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.integer "day_of_week_utc", null: false
    t.integer "hour_of_day_utc", null: false
    t.datetime "last_synced_at"
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.integer "view_count", default: 0, null: false
    t.bigint "watch_time_seconds", default: 0, null: false
    t.index ["last_synced_at"], name: "index_video_viewer_time_buckets_on_last_synced_at"
    t.index ["video_id", "day_of_week_utc", "hour_of_day_utc"], name: "index_viewer_time_buckets_uniq", unique: true
    t.check_constraint "day_of_week_utc >= 0 AND day_of_week_utc <= 6", name: "viewer_time_buckets_dow_range"
    t.check_constraint "hour_of_day_utc >= 0 AND hour_of_day_utc <= 23", name: "viewer_time_buckets_hour_range"
    t.check_constraint "view_count >= 0", name: "viewer_time_buckets_view_count_nonneg"
    t.check_constraint "watch_time_seconds >= 0", name: "viewer_time_buckets_watch_time_nonneg"
  end

  create_table "video_window_summaries", force: :cascade do |t|
    t.bigint "ad_impressions"
    t.decimal "average_view_duration", precision: 10, scale: 2
    t.decimal "average_view_percentage", precision: 10, scale: 6
    t.decimal "card_click_rate", precision: 10, scale: 6
    t.bigint "card_clicks", default: 0, null: false
    t.bigint "card_impressions", default: 0, null: false
    t.decimal "card_teaser_click_rate", precision: 10, scale: 6
    t.bigint "card_teaser_clicks", default: 0, null: false
    t.bigint "card_teaser_impressions", default: 0, null: false
    t.bigint "comments", default: 0, null: false
    t.decimal "cpm", precision: 12, scale: 4
    t.datetime "created_at", null: false
    t.bigint "dislikes", default: 0, null: false
    t.bigint "engaged_views", default: 0, null: false
    t.decimal "estimated_ad_revenue", precision: 12, scale: 4
    t.bigint "estimated_minutes_watched", default: 0, null: false
    t.bigint "estimated_red_minutes_watched", default: 0, null: false
    t.decimal "estimated_red_partner_revenue", precision: 12, scale: 4
    t.decimal "estimated_revenue", precision: 12, scale: 4
    t.decimal "gross_revenue", precision: 12, scale: 4
    t.bigint "likes", default: 0, null: false
    t.bigint "monetized_playbacks"
    t.decimal "playback_based_cpm", precision: 12, scale: 4
    t.bigint "red_views", default: 0, null: false
    t.bigint "shares", default: 0, null: false
    t.bigint "subscribers_gained", default: 0, null: false
    t.bigint "subscribers_lost", default: 0, null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.bigint "video_thumbnail_impressions", default: 0, null: false
    t.decimal "video_thumbnail_impressions_click_rate", precision: 10, scale: 6
    t.bigint "videos_added_to_playlists", default: 0, null: false
    t.bigint "videos_removed_from_playlists", default: 0, null: false
    t.bigint "views", default: 0, null: false
    t.enum "window", null: false, enum_type: "analytics_window"
    t.date "window_end", null: false
    t.date "window_start", null: false
    t.index ["video_id", "window"], name: "idx_video_window_summary_uniq", unique: true
    t.index ["video_id"], name: "index_video_window_summaries_on_video_id"
  end

  create_table "videos", force: :cascade do |t|
    t.string "category_id"
    t.bigint "channel_id", null: false
    t.bigint "comment_count", default: 0, null: false
    t.boolean "contains_synthetic_media", default: false, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.boolean "embeddable", default: true, null: false
    t.string "etag"
    t.datetime "last_diff_checked_at"
    t.text "last_sync_error"
    t.datetime "last_synced_at"
    t.bigint "like_count", default: 0, null: false
    t.boolean "made_for_kids_effective", default: false, null: false
    t.boolean "pre_publish_age_ok", default: false, null: false
    t.datetime "pre_publish_checked_at"
    t.boolean "pre_publish_end_screen_ok", default: false, null: false
    t.boolean "pre_publish_game_ok", default: false, null: false
    t.boolean "pre_publish_paid_promotion_ok", default: false, null: false
    t.integer "privacy_status", default: 0, null: false
    t.bigint "project_id"
    t.boolean "public_stats_viewable", default: true, null: false
    t.datetime "publish_at"
    t.datetime "published_at"
    t.boolean "self_declared_made_for_kids", default: false, null: false
    t.boolean "star", default: false, null: false
    t.jsonb "tags", default: [], null: false
    t.string "thumbnail_url"
    t.string "title", limit: 100, default: "", null: false
    t.datetime "title_changed_at"
    t.datetime "updated_at", null: false
    t.bigint "view_count", default: 0, null: false
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
  add_foreign_key "auth_audit_logs", "users", column: "acting_user_id"
  add_foreign_key "bulk_operation_items", "bulk_operations"
  add_foreign_key "bulk_operation_items", "videos"
  add_foreign_key "bundle_members", "bundles", on_delete: :cascade
  add_foreign_key "bundle_members", "games", on_delete: :cascade
  add_foreign_key "calendar_entries", "calendar_entries", column: "parent_entry_id", on_delete: :nullify
  add_foreign_key "calendar_entries", "channels", on_delete: :cascade
  add_foreign_key "calendar_entries", "games", on_delete: :cascade
  add_foreign_key "calendar_entries", "milestone_rules", on_delete: :nullify
  add_foreign_key "calendar_entries", "projects", on_delete: :nullify
  add_foreign_key "calendar_entries", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "calendar_entries", "videos", on_delete: :cascade
  add_foreign_key "channel_change_logs", "channels", on_delete: :cascade
  add_foreign_key "channel_change_logs", "users", column: "changed_by_user_id", on_delete: :restrict
  add_foreign_key "channel_dailies", "channels", on_delete: :cascade
  add_foreign_key "channel_window_summaries", "channels", on_delete: :cascade
  add_foreign_key "channels", "youtube_connections"
  add_foreign_key "footages", "games"
  add_foreign_key "footages", "projects"
  add_foreign_key "game_developers", "companies", on_delete: :cascade
  add_foreign_key "game_developers", "games", on_delete: :cascade
  add_foreign_key "game_genres", "games", on_delete: :cascade
  add_foreign_key "game_genres", "genres", on_delete: :cascade
  add_foreign_key "game_platform_ownerships", "games", on_delete: :cascade
  add_foreign_key "game_platform_ownerships", "platforms", on_delete: :restrict
  add_foreign_key "game_platforms", "games", on_delete: :cascade
  add_foreign_key "game_platforms", "platforms", on_delete: :cascade
  add_foreign_key "game_publishers", "companies", on_delete: :cascade
  add_foreign_key "game_publishers", "games", on_delete: :cascade
  add_foreign_key "games", "collections"
  add_foreign_key "games", "games", column: "version_parent_id", on_delete: :nullify
  add_foreign_key "games", "genres", column: "primary_genre_id", on_delete: :nullify
  add_foreign_key "import_jobs", "channels", on_delete: :cascade
  add_foreign_key "import_jobs", "users", column: "enqueued_by_id", on_delete: :restrict
  add_foreign_key "milestone_rules", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "notes", "projects"
  add_foreign_key "notifications", "calendar_entries", column: "source_calendar_entry_id", on_delete: :cascade
  add_foreign_key "notifications", "milestone_rules", column: "source_milestone_rule_id", on_delete: :nullify
  add_foreign_key "notifications", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "oauth_access_grants", "oauth_applications", column: "application_id"
  add_foreign_key "oauth_access_tokens", "oauth_applications", column: "application_id"
  add_foreign_key "playlist_videos", "playlists"
  add_foreign_key "playlist_videos", "videos"
  add_foreign_key "playlists", "channels"
  add_foreign_key "project_references", "projects"
  add_foreign_key "rejected_video_imports", "channels", on_delete: :cascade
  add_foreign_key "rejected_video_imports", "users", column: "rejected_by_id", on_delete: :restrict
  add_foreign_key "sessions", "users"
  add_foreign_key "timelines", "projects"
  add_foreign_key "timelines", "videos"
  add_foreign_key "top_videos_windows", "channels", on_delete: :cascade
  add_foreign_key "top_videos_windows", "videos", on_delete: :cascade
  add_foreign_key "totp_backup_codes", "users"
  add_foreign_key "video_change_logs", "users", column: "changed_by_user_id", on_delete: :nullify
  add_foreign_key "video_change_logs", "videos", on_delete: :cascade
  add_foreign_key "video_chapters", "videos", on_delete: :cascade
  add_foreign_key "video_dailies", "videos", on_delete: :cascade
  add_foreign_key "video_daily_by_age_group_genders", "videos", on_delete: :cascade
  add_foreign_key "video_daily_by_countries", "videos", on_delete: :cascade
  add_foreign_key "video_daily_by_device_types", "videos", on_delete: :cascade
  add_foreign_key "video_daily_by_operating_systems", "videos", on_delete: :cascade
  add_foreign_key "video_daily_by_subscribed_statuses", "videos", on_delete: :cascade
  add_foreign_key "video_daily_by_traffic_sources", "videos", on_delete: :cascade
  add_foreign_key "video_diffs", "users", column: "resolved_by_user_id", on_delete: :nullify
  add_foreign_key "video_diffs", "videos", on_delete: :cascade
  add_foreign_key "video_end_screens", "videos", on_delete: :cascade
  add_foreign_key "video_game_links", "bundles", on_delete: :cascade
  add_foreign_key "video_game_links", "games", on_delete: :cascade
  add_foreign_key "video_game_links", "users", column: "created_by_user_id", on_delete: :nullify
  add_foreign_key "video_game_links", "videos", on_delete: :cascade
  add_foreign_key "video_retentions", "videos", on_delete: :cascade
  add_foreign_key "video_stats", "videos"
  add_foreign_key "video_uploads", "channels"
  add_foreign_key "video_uploads", "videos"
  add_foreign_key "video_viewer_time_buckets", "videos", on_delete: :cascade
  add_foreign_key "video_window_summaries", "videos", on_delete: :cascade
  add_foreign_key "videos", "channels"
  add_foreign_key "videos", "projects", on_delete: :nullify
  add_foreign_key "videos", "youtube_connections"
  add_foreign_key "youtube_api_calls", "users"
  add_foreign_key "youtube_api_calls", "youtube_connections"
  add_foreign_key "youtube_connections", "users"
end
