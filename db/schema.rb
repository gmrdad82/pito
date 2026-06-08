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

ActiveRecord::Schema[8.1].define(version: 2026_06_08_003432) do
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

  create_table "api_requests", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "endpoint"
    t.string "provider", null: false
    t.integer "units"
    t.index ["provider", "created_at"], name: "index_api_requests_on_provider_and_created_at"
  end

  create_table "app_settings", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "google_oauth_client_id"
    t.text "google_oauth_client_secret"
    t.string "key"
    t.integer "totp_last_used_step"
    t.text "totp_seed_encrypted"
    t.datetime "updated_at", null: false
    t.text "value"
    t.text "voyage_api_key"
    t.index ["key"], name: "index_app_settings_on_key", unique: true
  end

  create_table "channels", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "handle"
    t.datetime "last_synced_at"
    t.string "title"
    t.datetime "updated_at", null: false
    t.integer "video_count"
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
    t.text "draft"
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
    t.string "embedded_digest"
    t.bigint "igdb_id"
    t.decimal "igdb_rating", precision: 5, scale: 2
    t.integer "igdb_rating_count"
    t.string "igdb_slug"
    t.datetime "igdb_synced_at"
    t.text "last_sync_error"
    t.text "platforms", default: [], null: false, array: true
    t.text "player_perspectives", default: [], null: false, array: true
    t.date "release_date"
    t.integer "release_day"
    t.integer "release_month"
    t.integer "release_quarter"
    t.integer "release_year"
    t.boolean "resyncing", default: false, null: false
    t.integer "score"
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(summary, ''::text)))", stored: true
    t.text "summary"
    t.vector "summary_embedding", limit: 1024
    t.text "themes", default: [], null: false, array: true
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
    t.index ["player_perspectives"], name: "index_games_on_player_perspectives", using: :gin
    t.index ["release_month", "release_day"], name: "index_games_on_release_month_and_release_day"
    t.index ["release_year"], name: "index_games_on_release_year"
    t.index ["score"], name: "index_games_on_score"
    t.index ["search_vector"], name: "index_games_on_search_vector", using: :gin
    t.index ["summary_embedding"], name: "index_games_on_summary_embedding_hnsw", opclass: :vector_cosine_ops, using: :hnsw
    t.index ["themes"], name: "index_games_on_themes", using: :gin
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

  create_table "notifications", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "message", null: false
    t.datetime "read_at"
    t.datetime "updated_at", null: false
  end

  create_table "solid_cable_messages", force: :cascade do |t|
    t.binary "channel", null: false
    t.bigint "channel_hash", null: false
    t.datetime "created_at", null: false
    t.binary "payload", null: false
    t.index ["channel"], name: "index_solid_cable_messages_on_channel"
    t.index ["channel_hash"], name: "index_solid_cable_messages_on_channel_hash"
    t.index ["created_at"], name: "index_solid_cable_messages_on_created_at"
  end

  create_table "solid_cache_entries", force: :cascade do |t|
    t.integer "byte_size", null: false
    t.datetime "created_at", null: false
    t.binary "key", null: false
    t.bigint "key_hash", null: false
    t.binary "value", null: false
    t.index ["byte_size"], name: "index_solid_cache_entries_on_byte_size"
    t.index ["key_hash", "byte_size"], name: "index_solid_cache_entries_on_key_hash_and_byte_size"
    t.index ["key_hash"], name: "index_solid_cache_entries_on_key_hash", unique: true
  end

  create_table "solid_queue_blocked_executions", force: :cascade do |t|
    t.string "concurrency_key", null: false
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["concurrency_key", "priority", "job_id"], name: "idx_on_concurrency_key_priority_job_id_d4bdd8da1e"
    t.index ["expires_at", "concurrency_key"], name: "idx_on_expires_at_concurrency_key_c20fd0827b"
    t.index ["job_id"], name: "index_solid_queue_blocked_executions_on_job_id", unique: true
  end

  create_table "solid_queue_claimed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.bigint "process_id"
    t.index ["job_id"], name: "index_solid_queue_claimed_executions_on_job_id", unique: true
    t.index ["process_id", "job_id"], name: "index_solid_queue_claimed_executions_on_process_id_and_job_id"
  end

  create_table "solid_queue_failed_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.text "error"
    t.bigint "job_id", null: false
    t.index ["job_id"], name: "index_solid_queue_failed_executions_on_job_id", unique: true
  end

  create_table "solid_queue_jobs", force: :cascade do |t|
    t.string "active_job_id"
    t.text "arguments"
    t.string "class_name", null: false
    t.string "concurrency_key"
    t.datetime "created_at", null: false
    t.datetime "finished_at"
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at"
    t.datetime "updated_at", null: false
    t.index ["active_job_id"], name: "index_solid_queue_jobs_on_active_job_id"
    t.index ["class_name"], name: "index_solid_queue_jobs_on_class_name"
    t.index ["finished_at"], name: "index_solid_queue_jobs_on_finished_at"
    t.index ["queue_name", "finished_at"], name: "index_solid_queue_jobs_on_queue_name_and_finished_at"
    t.index ["scheduled_at", "finished_at"], name: "index_solid_queue_jobs_on_scheduled_at_and_finished_at"
  end

  create_table "solid_queue_pauses", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "queue_name", null: false
    t.index ["queue_name"], name: "index_solid_queue_pauses_on_queue_name", unique: true
  end

  create_table "solid_queue_processes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "hostname"
    t.string "kind", null: false
    t.datetime "last_heartbeat_at", null: false
    t.text "metadata"
    t.string "name", null: false
    t.integer "pid", null: false
    t.bigint "supervisor_id"
    t.index ["last_heartbeat_at"], name: "index_solid_queue_processes_on_last_heartbeat_at"
    t.index ["name", "supervisor_id"], name: "index_solid_queue_processes_on_name_and_supervisor_id", unique: true
    t.index ["supervisor_id"], name: "index_solid_queue_processes_on_supervisor_id"
  end

  create_table "solid_queue_ready_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.index ["job_id"], name: "index_solid_queue_ready_executions_on_job_id", unique: true
    t.index ["priority", "job_id"], name: "index_solid_queue_ready_executions_on_priority_and_job_id"
    t.index ["queue_name", "priority", "job_id"], name: "idx_on_queue_name_priority_job_id_b116c992cd"
  end

  create_table "solid_queue_recurring_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.datetime "run_at", null: false
    t.string "task_key", null: false
    t.index ["job_id"], name: "index_solid_queue_recurring_executions_on_job_id", unique: true
    t.index ["task_key", "run_at"], name: "index_solid_queue_recurring_executions_on_task_key_and_run_at", unique: true
  end

  create_table "solid_queue_recurring_tasks", force: :cascade do |t|
    t.text "arguments"
    t.string "class_name"
    t.string "command", limit: 2048
    t.datetime "created_at", null: false
    t.text "description"
    t.string "key", null: false
    t.integer "priority", default: 0
    t.string "queue_name"
    t.string "schedule", null: false
    t.boolean "static", default: true, null: false
    t.datetime "updated_at", null: false
    t.index ["key"], name: "index_solid_queue_recurring_tasks_on_key", unique: true
    t.index ["static"], name: "index_solid_queue_recurring_tasks_on_static"
  end

  create_table "solid_queue_scheduled_executions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "job_id", null: false
    t.integer "priority", default: 0, null: false
    t.string "queue_name", null: false
    t.datetime "scheduled_at", null: false
    t.index ["job_id"], name: "index_solid_queue_scheduled_executions_on_job_id", unique: true
    t.index ["scheduled_at", "priority", "job_id"], name: "idx_on_scheduled_at_priority_job_id_cf978ceebd"
  end

  create_table "solid_queue_semaphores", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "expires_at", null: false
    t.string "key", null: false
    t.datetime "updated_at", null: false
    t.integer "value", default: 1, null: false
    t.index ["expires_at"], name: "index_solid_queue_semaphores_on_expires_at"
    t.index ["key", "value"], name: "index_solid_queue_semaphores_on_key_and_value"
    t.index ["key"], name: "index_solid_queue_semaphores_on_key", unique: true
  end

  create_table "stats", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "entity_id", null: false
    t.string "entity_type", null: false
    t.string "kind", null: false
    t.datetime "synced_at"
    t.datetime "updated_at", null: false
    t.bigint "value"
    t.index ["entity_type", "entity_id", "kind"], name: "index_stats_on_entity_and_kind", unique: true
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

  create_table "videos", force: :cascade do |t|
    t.string "category_id"
    t.bigint "channel_id", null: false
    t.bigint "comment_count", default: 0, null: false
    t.datetime "created_at", null: false
    t.text "description"
    t.integer "duration_seconds"
    t.string "embedded_digest"
    t.string "etag"
    t.datetime "last_synced_at"
    t.bigint "like_count", default: 0, null: false
    t.integer "privacy_status", default: 0, null: false
    t.datetime "publish_at"
    t.datetime "published_at"
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('english'::regconfig, (((COALESCE(title, ''::character varying))::text || ' '::text) || COALESCE(description, ''::text)))", stored: true
    t.vector "summary_embedding", limit: 1024
    t.text "tags", default: [], null: false, array: true
    t.string "title", null: false
    t.datetime "updated_at", null: false
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
  add_foreign_key "game_publishers", "companies", on_delete: :cascade
  add_foreign_key "game_publishers", "games", on_delete: :cascade
  add_foreign_key "solid_queue_blocked_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_claimed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_failed_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_ready_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_recurring_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "solid_queue_scheduled_executions", "solid_queue_jobs", column: "job_id", on_delete: :cascade
  add_foreign_key "turns", "conversations"
  add_foreign_key "video_game_links", "games", on_delete: :cascade
  add_foreign_key "video_game_links", "videos", on_delete: :cascade
  add_foreign_key "videos", "channels"
end
