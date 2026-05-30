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

ActiveRecord::Schema[8.1].define(version: 2026_05_30_012344) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "citext"
  enable_extension "pg_catalog.plpgsql"
  enable_extension "pg_trgm"
  enable_extension "pgcrypto"
  enable_extension "unaccent"
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
    t.text "google_oauth_client_id"
    t.text "google_oauth_client_secret"
    t.string "key"
    t.datetime "totp_disabled_at"
    t.datetime "totp_enabled_at"
    t.integer "totp_last_used_step"
    t.text "totp_seed_encrypted"
    t.datetime "updated_at", null: false
    t.text "value"
    t.text "voyage_api_key"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "channels", force: :cascade do |t|
    t.string "avatar_url"
    t.string "banner_url"
    t.datetime "created_at", null: false
    t.text "description"
    t.string "handle"
    t.datetime "last_synced_at"
    t.bigint "subscriber_count"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "video_count"
    t.bigint "view_count"
    t.string "youtube_channel_id", null: false
    t.bigint "youtube_connection_id"
    t.index ["last_synced_at"], name: "index_channels_on_last_synced_at"
    t.index ["youtube_channel_id"], name: "index_channels_on_youtube_channel_id", unique: true
    t.index ["youtube_connection_id"], name: "index_channels_on_youtube_connection_id"
  end

  create_table "companies", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "igdb_id", null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["igdb_id"], name: "index_companies_on_igdb_id", unique: true
  end

  create_table "conversations", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "title"
    t.datetime "updated_at", null: false
    t.uuid "uuid", null: false
    t.index ["uuid"], name: "index_conversations_on_uuid", unique: true
  end

  create_table "events", force: :cascade do |t|
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "kind", null: false
    t.jsonb "payload", default: {}, null: false
    t.integer "position", null: false
    t.bigint "turn_id", null: false
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "position"], name: "index_events_on_conversation_id_and_position", unique: true
    t.index ["conversation_id"], name: "index_events_on_conversation_id"
    t.index ["turn_id"], name: "index_events_on_turn_id"
  end

  create_table "footages", force: :cascade do |t|
    t.string "aspect_ratio"
    t.text "audio_track_names", default: [], null: false, array: true
    t.datetime "created_at", null: false
    t.integer "duration_seconds"
    t.string "filename", null: false
    t.decimal "fps", precision: 6, scale: 3
    t.bigint "game_id", null: false
    t.boolean "needs_grading", default: false, null: false
    t.string "orientation"
    t.string "resolution"
    t.datetime "updated_at", null: false
    t.index ["game_id", "filename"], name: "index_footages_on_game_id_and_filename", unique: true
  end

  create_table "game_developers", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_game_developers_on_company_id"
    t.index ["game_id", "company_id"], name: "index_game_developers_on_game_id_and_company_id", unique: true
  end

  create_table "game_genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.bigint "genre_id", null: false
    t.integer "position"
    t.datetime "updated_at", null: false
    t.index ["game_id", "genre_id"], name: "index_game_genres_on_game_id_and_genre_id", unique: true
    t.index ["game_id", "position"], name: "index_game_genres_on_game_id_and_position"
    t.index ["genre_id"], name: "index_game_genres_on_genre_id"
  end

  create_table "game_platform_ownerships", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.text "platform_token", null: false
    t.datetime "updated_at", null: false
    t.index ["game_id", "platform_token"], name: "index_game_platform_ownerships_on_game_id_and_platform_token", unique: true
    t.check_constraint "platform_token = ANY (ARRAY['ps'::text, 'switch'::text, 'steam'::text])", name: "game_platform_ownerships_platform_token_allowlist"
  end

  create_table "game_publishers", force: :cascade do |t|
    t.bigint "company_id", null: false
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.datetime "updated_at", null: false
    t.index ["company_id"], name: "index_game_publishers_on_company_id"
    t.index ["game_id", "company_id"], name: "index_game_publishers_on_game_id_and_company_id", unique: true
  end

  create_table "games", force: :cascade do |t|
    t.decimal "aggregated_rating", precision: 5, scale: 2
    t.integer "aggregated_rating_count"
    t.text "alternative_names", default: [], null: false, array: true
    t.string "cover_image_id"
    t.datetime "created_at", null: false
    t.string "igdb_checksum"
    t.bigint "igdb_id"
    t.decimal "igdb_rating", precision: 5, scale: 2
    t.integer "igdb_rating_count"
    t.string "igdb_slug"
    t.datetime "igdb_synced_at"
    t.text "notes"
    t.text "platforms", default: [], null: false, array: true
    t.date "played_at"
    t.bigint "primary_genre_id"
    t.date "release_date"
    t.integer "release_precision"
    t.integer "release_year"
    t.integer "score"
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(summary, ''::text)))", stored: true
    t.text "summary"
    t.vector "summary_embedding", limit: 1024
    t.string "title", default: "Untitled game", null: false
    t.decimal "total_rating", precision: 5, scale: 2
    t.integer "total_rating_count"
    t.integer "ttb_completionist_seconds"
    t.integer "ttb_extras_seconds"
    t.integer "ttb_main_seconds"
    t.datetime "updated_at", null: false
    t.index ["alternative_names"], name: "index_games_on_alternative_names", using: :gin
    t.index ["igdb_id"], name: "index_games_on_igdb_id", unique: true, where: "(igdb_id IS NOT NULL)"
    t.index ["igdb_slug"], name: "index_games_on_igdb_slug", unique: true, where: "(igdb_slug IS NOT NULL)"
    t.index ["igdb_synced_at"], name: "index_games_on_igdb_synced_at"
    t.index ["primary_genre_id"], name: "index_games_on_primary_genre_id"
    t.index ["release_year"], name: "index_games_on_release_year"
    t.index ["score"], name: "index_games_on_score"
    t.index ["search_vector"], name: "index_games_on_search_vector", using: :gin
    t.index ["summary_embedding"], name: "index_games_on_summary_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["title"], name: "index_games_on_title_trigram", opclass: :gin_trgm_ops, using: :gin
  end

  create_table "genres", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "igdb_id", null: false
    t.string "name", null: false
    t.string "slug"
    t.datetime "updated_at", null: false
    t.index ["igdb_id"], name: "index_genres_on_igdb_id", unique: true
  end

  create_table "turns", force: :cascade do |t|
    t.datetime "completed_at"
    t.bigint "conversation_id", null: false
    t.datetime "created_at", null: false
    t.string "input_kind", null: false
    t.string "input_text", null: false
    t.integer "position", null: false
    t.datetime "started_at"
    t.datetime "updated_at", null: false
    t.index ["conversation_id", "position"], name: "index_turns_on_conversation_id_and_position", unique: true
    t.index ["conversation_id"], name: "index_turns_on_conversation_id"
  end

  create_table "video_game_links", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "game_id", null: false
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["game_id"], name: "index_video_game_links_on_game_id"
    t.index ["video_id", "game_id"], name: "index_video_game_links_on_video_id_and_game_id", unique: true
  end

  create_table "video_previews", force: :cascade do |t|
    t.boolean "allow_embedding"
    t.boolean "automatic_chapters"
    t.boolean "automatic_concepts"
    t.boolean "automatic_places"
    t.string "category_id"
    t.boolean "contains_altered_content"
    t.datetime "created_at", null: false
    t.text "description"
    t.text "error_message"
    t.string "game_title"
    t.boolean "made_for_kids"
    t.boolean "notify_subscribers"
    t.boolean "paid_promotion"
    t.datetime "published_at"
    t.integer "shorts_remixing"
    t.integer "status", default: 0, null: false
    t.text "tags", array: true
    t.string "title"
    t.datetime "updated_at", null: false
    t.bigint "video_id", null: false
    t.index ["video_id"], name: "index_video_previews_on_video_id"
  end

  create_table "videos", force: :cascade do |t|
    t.string "category_id"
    t.bigint "channel_id", null: false
    t.bigint "comment_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.string "etag"
    t.datetime "last_synced_at"
    t.bigint "like_count", default: 0, null: false
    t.integer "privacy_status", default: 0, null: false
    t.datetime "publish_at"
    t.datetime "published_at"
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)))", stored: true
    t.vector "summary_embedding", limit: 1024
    t.text "tags", default: [], null: false, array: true
    t.string "thumbnail_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.bigint "view_count", default: 0, null: false
    t.string "youtube_video_id", null: false
    t.index ["channel_id"], name: "index_videos_on_channel_id"
    t.index ["privacy_status"], name: "index_videos_on_privacy_status"
    t.index ["publish_at"], name: "index_videos_on_publish_at", where: "(publish_at IS NOT NULL)"
    t.index ["published_at"], name: "index_videos_on_published_at"
    t.index ["search_vector"], name: "index_videos_on_search_vector", using: :gin
    t.index ["summary_embedding"], name: "index_videos_on_summary_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["tags"], name: "index_videos_on_tags", using: :gin
    t.index ["title"], name: "index_videos_on_title_trigram", opclass: :gin_trgm_ops, using: :gin
    t.index ["youtube_video_id"], name: "index_videos_on_youtube_video_id", unique: true
  end

  create_table "youtube_connections", force: :cascade do |t|
    t.text "access_token", null: false
    t.datetime "created_at", null: false
    t.string "email", null: false
    t.datetime "expires_at", null: false
    t.string "google_subject_id", null: false
    t.datetime "last_authorized_at", null: false
    t.boolean "needs_reauth", default: false, null: false
    t.text "refresh_token"
    t.jsonb "scopes", default: [], null: false
    t.datetime "updated_at", null: false
    t.index ["google_subject_id"], name: "index_youtube_connections_on_google_subject_id", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "channels", "youtube_connections", on_delete: :nullify
  add_foreign_key "events", "conversations"
  add_foreign_key "events", "turns"
  add_foreign_key "footages", "games", on_delete: :cascade
  add_foreign_key "game_developers", "companies", on_delete: :cascade
  add_foreign_key "game_developers", "games", on_delete: :cascade
  add_foreign_key "game_genres", "games", on_delete: :cascade
  add_foreign_key "game_genres", "genres", on_delete: :cascade
  add_foreign_key "game_platform_ownerships", "games", on_delete: :cascade
  add_foreign_key "game_publishers", "companies", on_delete: :cascade
  add_foreign_key "game_publishers", "games", on_delete: :cascade
  add_foreign_key "games", "genres", column: "primary_genre_id", on_delete: :nullify
  add_foreign_key "turns", "conversations"
  add_foreign_key "video_game_links", "games", on_delete: :cascade
  add_foreign_key "video_game_links", "videos", on_delete: :cascade
  add_foreign_key "video_previews", "videos", on_delete: :cascade
  add_foreign_key "videos", "channels"
end
