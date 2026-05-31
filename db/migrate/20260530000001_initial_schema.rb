# frozen_string_literal: true

# Plan 4 / P5 — Fresh single-file initial schema.
#
# Replaces the prior multi-file migration history (beta_baseline +
# add_search_vector_to_games/videos + add_trigram_indexes +
# create_conversations_turns_events) with ONE migration that rebuilds the
# schema from scratch against an empty database (db:drop → db:create →
# db:migrate per P5).
#
# Authored across three plan steps that all land in THIS file:
#   * T5.3       — scaffold: extensions + every kept table (current form) + FKs.
#   * T5.4–T5.12 — per-table column edits, video_previews, Active Storage.
#   * T5.13      — search_vector generated columns + HNSW/trigram GIN indexes.
#
# `sessions` and `totp_backup_codes` are intentionally NOT recreated
# (dropped in P2; T5.6 / T5.6b). Extensions are enabled first because the
# vector columns + GIN/HNSW indexes below depend on them.
class InitialSchema < ActiveRecord::Migration[8.1]
  def change
    # ── Extensions (verified/preserved in T5.13) ─────────────────────────
    enable_extension "pgcrypto"
    enable_extension "citext"
    enable_extension "vector"
    enable_extension "pg_trgm"
    enable_extension "unaccent"

    # ── Auth / config ────────────────────────────────────────────────────

    create_table :youtube_connections do |t|
      t.string   :google_subject_id,  null: false
      t.string   :email,              null: false
      t.text     :access_token,       null: false
      t.text     :refresh_token
      t.jsonb    :scopes,             null: false, default: []
      t.datetime :expires_at,         null: false
      t.datetime :last_authorized_at, null: false
      t.boolean  :needs_reauth,       null: false, default: false
      t.timestamps

      t.index :google_subject_id, unique: true
    end

    create_table :app_settings do |t|
      t.string :key
      t.text   :value

      # Singleton-row TOTP state (6-digit only; backup codes removed in P2).
      t.text     :totp_seed_encrypted
      t.datetime :totp_enabled_at
      t.datetime :totp_disabled_at
      t.integer  :totp_last_used_step

      # Singleton-row pre-allocated API key columns (AR-encrypted).
      t.text :google_oauth_client_id
      t.text :google_oauth_client_secret
      t.text :voyage_api_key

      t.timestamps

      # Postgres allows multiple NULLs under a UNIQUE constraint — wanted for
      # the singleton + key/value mix.
      t.index :key, unique: true
    end

    # ── YouTube domain ──────────────────────────────────────────────────

    create_table :channels do |t|
      t.string :youtube_channel_id, null: false
      t.bigint :youtube_connection_id

      t.string :title
      t.string :handle
      t.text   :description

      t.string :avatar_url
      t.string :banner_url

      t.bigint  :subscriber_count
      t.bigint  :view_count
      t.integer :video_count

      t.datetime :last_synced_at
      t.timestamps

      t.index :youtube_channel_id, unique: true
      t.index :youtube_connection_id
      t.index :last_synced_at
    end

    create_table :videos do |t|
      t.string :youtube_video_id, null: false
      t.bigint :channel_id,       null: false

      t.string :title,        null: false
      t.text   :description
      t.text   :tags,         array: true, null: false, default: []

      t.string  :category_id
      t.integer :privacy_status, null: false, default: 0

      t.datetime :publish_at
      t.datetime :published_at

      t.string :thumbnail_url

      t.bigint :view_count,    null: false, default: 0
      t.bigint :like_count,    null: false, default: 0
      t.bigint :comment_count, null: false, default: 0

      t.integer :duration_seconds

      t.datetime :last_synced_at
      t.string   :etag # YouTube resource etag for incremental import (P31)

      t.vector :summary_embedding, limit: 1024

      t.timestamps

      t.index :youtube_video_id, unique: true
      t.index :channel_id
      t.index :privacy_status
      t.index :publish_at,   where: "publish_at IS NOT NULL"
      t.index :published_at
      t.index :tags, using: :gin
      # search_vector (+ GIN), summary_embedding HNSW, title trigram → T5.13
    end

    # The one writable surface: staged metadata edits, published to YouTube by
    # /update videos (P33). nil column = not staged / inherit from Video.
    create_table :video_previews do |t|
      t.references :video, null: false, index: true,
                   foreign_key: { on_delete: :cascade }

      t.integer  :status, null: false, default: 0 # draft/publishing/published/failed (T6.8)
      t.datetime :published_at
      t.text     :error_message

      # Staged edits (YouTube Studio parity).
      t.string :title
      t.text   :description
      t.text   :tags, array: true
      t.string :category_id
      t.string :game_title

      t.boolean :made_for_kids
      t.boolean :paid_promotion
      t.boolean :contains_altered_content # AI / altered-content disclosure
      t.boolean :allow_embedding
      t.boolean :automatic_chapters
      t.boolean :automatic_places
      t.boolean :automatic_concepts
      t.boolean :notify_subscribers
      t.integer :shorts_remixing # video_audio / audio_only / none

      t.timestamps
    end

    # ── IGDB reference + games ─────────────────────────────────────────

    create_table :companies do |t|
      t.bigint :igdb_id, null: false
      t.string :name,    null: false
      t.string :slug
      t.timestamps

      t.index :igdb_id, unique: true
    end

    create_table :genres do |t|
      t.bigint :igdb_id, null: false
      t.string :name,    null: false
      t.string :slug
      t.timestamps

      t.index :igdb_id, unique: true
    end

    create_table :games do |t|
      t.bigint :igdb_id
      t.string :igdb_slug

      t.string :title, null: false, default: "Untitled game"
      t.text   :summary

      t.string :cover_image_id
      t.text   :platforms, array: true, null: false, default: []

      # Release date as independent precision components keyed off
      # nullability (P8 / docs/architecture.md § "Game release-date
      # representation"). `release_date` is the recomputed lower-bound
      # used for sorts / ranges / `released?`; the components carry the
      # known precision. Each is NULL when not known at that grain.
      t.date    :release_date
      t.integer :release_year
      t.integer :release_quarter # 1..4, NULL unless quarter precision
      t.integer :release_month   # 1..12, NULL when only year/quarter known
      t.integer :release_day     # 1..31, NULL when only month known

      # 3 ratings + counts.
      t.decimal :igdb_rating,             precision: 5, scale: 2
      t.integer :igdb_rating_count
      t.decimal :total_rating,            precision: 5, scale: 2
      t.integer :total_rating_count
      t.decimal :aggregated_rating,       precision: 5, scale: 2
      t.integer :aggregated_rating_count

      # Synthesized 0–100 score (vote-weighted; Pito::Game::ScoreCalculator, P7).
      t.integer :score

      # 3 TTBs.
      t.integer :ttb_main_seconds
      t.integer :ttb_extras_seconds
      t.integer :ttb_completionist_seconds

      t.text :alternative_names, array: true, null: false, default: []

      t.bigint :primary_genre_id

      t.datetime :igdb_synced_at

      t.date :played_at
      t.text :notes

      t.vector :summary_embedding, limit: 1024

      t.timestamps

      t.index :igdb_id,               unique: true, where: "igdb_id IS NOT NULL"
      t.index :igdb_slug,             unique: true, where: "igdb_slug IS NOT NULL"
      t.index :primary_genre_id
      t.index :igdb_synced_at
      t.index :release_year
      t.index [ :release_month, :release_day ] # "Christmas in any year"-style queries
      t.index :score
      t.index :alternative_names, using: :gin
      # search_vector (+ GIN), summary_embedding HNSW, title trigram → T5.13
    end

    create_table :game_genres do |t|
      t.bigint  :game_id,  null: false
      t.bigint  :genre_id, null: false
      t.integer :position
      t.timestamps

      t.index [ :game_id, :genre_id ], unique: true
      t.index [ :game_id, :position ]
      t.index :genre_id
    end

    create_table :game_developers do |t|
      t.bigint :game_id,    null: false
      t.bigint :company_id, null: false
      t.timestamps

      t.index [ :game_id, :company_id ], unique: true
      t.index :company_id
    end

    create_table :game_publishers do |t|
      t.bigint :game_id,    null: false
      t.bigint :company_id, null: false
      t.timestamps

      t.index [ :game_id, :company_id ], unique: true
      t.index :company_id
    end

    create_table :game_platform_ownerships do |t|
      t.bigint :game_id,        null: false
      t.text   :platform_token, null: false
      t.timestamps

      t.index [ :game_id, :platform_token ], unique: true
      t.check_constraint "platform_token IN ('ps', 'switch', 'steam')",
                         name: "game_platform_ownerships_platform_token_allowlist"
    end

    create_table :video_game_links do |t|
      t.bigint :video_id, null: false
      t.bigint :game_id,  null: false
      t.timestamps

      t.index [ :video_id, :game_id ], unique: true
      t.index :game_id
    end

    create_table :footages do |t|
      t.bigint :game_id, null: false

      t.string :filename, null: false

      t.integer :duration_seconds
      t.string  :resolution
      t.string  :aspect_ratio
      t.decimal :fps, precision: 6, scale: 3

      t.integer :bit_depth, null: false, default: 8

      t.text :audio_track_names, array: true, null: false, default: []

      # ffprobe-derived grading + layout (P15).
      t.boolean :needs_grading, null: false, default: false
      t.string  :orientation

      t.timestamps

      # filename unique scoped to game; composite covers game_id FK lookups.
      t.index [ :game_id, :filename ], unique: true
    end

    # ── Chat: conversations / turns / events ────────────────────────────

    create_table :conversations do |t|
      t.uuid   :uuid,  null: false # routing id for /chat/:uuid; model-generated (T6.5)
      t.string :title
      t.timestamps

      t.index :uuid, unique: true
    end

    create_table :turns do |t|
      t.references :conversation, null: false, foreign_key: true, index: true
      t.integer :position,   null: false
      t.string  :input_kind, null: false
      t.string  :input_text, null: false

      # Async dispatch timing (P23); #elapsed_seconds in T6.6.
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps

      t.index [ :conversation_id, :position ], unique: true
    end

    create_table :events do |t|
      t.references :conversation, null: false, foreign_key: true, index: true
      t.references :turn,         null: false, foreign_key: true, index: true
      t.integer :position, null: false
      t.string  :kind,     null: false
      t.jsonb   :payload,  null: false, default: {}
      t.timestamps

      t.index [ :conversation_id, :position ], unique: true
    end

    # ── Active Storage (VideoPreview#thumbnail; backed by the `local` Disk
    #    service → /var/lib/pito-assets volume) ──────────────────────────

    create_table :active_storage_blobs do |t|
      t.string   :key,          null: false
      t.string   :filename,     null: false
      t.string   :content_type
      t.text     :metadata
      t.string   :service_name, null: false
      t.bigint   :byte_size,    null: false
      t.string   :checksum
      t.datetime :created_at,   null: false

      t.index [ :key ], unique: true
    end

    create_table :active_storage_attachments do |t|
      t.string     :name,   null: false
      t.references :record, null: false, polymorphic: true, index: false
      t.references :blob,   null: false

      t.datetime :created_at, null: false

      t.index [ :record_type, :record_id, :name, :blob_id ],
              name: "index_active_storage_attachments_uniqueness", unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    create_table :active_storage_variant_records do |t|
      t.belongs_to :blob, null: false, index: false
      t.string :variation_digest, null: false

      t.index [ :blob_id, :variation_digest ],
              name: "index_active_storage_variant_records_uniqueness", unique: true
      t.foreign_key :active_storage_blobs, column: :blob_id
    end

    # ── Foreign keys ───────────────────────────────────────────────────

    add_foreign_key :channels, :youtube_connections, on_delete: :nullify
    add_foreign_key :videos,   :channels

    add_foreign_key :games, :genres, column: :primary_genre_id, on_delete: :nullify

    add_foreign_key :game_genres,     :games,     on_delete: :cascade
    add_foreign_key :game_genres,     :genres,    on_delete: :cascade
    add_foreign_key :game_developers, :games,     on_delete: :cascade
    add_foreign_key :game_developers, :companies, on_delete: :cascade
    add_foreign_key :game_publishers, :games,     on_delete: :cascade
    add_foreign_key :game_publishers, :companies, on_delete: :cascade

    add_foreign_key :game_platform_ownerships, :games, on_delete: :cascade

    add_foreign_key :video_game_links, :videos, on_delete: :cascade
    add_foreign_key :video_game_links, :games,  on_delete: :cascade

    # game_id is null:false (T5.4) — a footage cannot outlive its game.
    add_foreign_key :footages, :games, on_delete: :cascade

    # ── Search infrastructure (T5.13) ──────────────────────────────────
    # Extensions (vector, pg_trgm, unaccent) are enabled at the top of this
    # migration. The tsvector columns are GENERATED ALWAYS … STORED, added via
    # raw SQL (PG generated-column expressions aren't expressible through the
    # column DSL); kept in sync by Postgres automatically.

    execute <<~SQL
      ALTER TABLE games ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english', coalesce(title, '') || ' ' || coalesce(summary, ''))
        ) STORED;
    SQL
    add_index :games, :search_vector, using: :gin

    execute <<~SQL
      ALTER TABLE videos ADD COLUMN search_vector tsvector
        GENERATED ALWAYS AS (
          to_tsvector('english', coalesce(title, '') || ' ' || coalesce(description, ''))
        ) STORED;
    SQL
    add_index :videos, :search_vector, using: :gin

    # Cosine-distance HNSW indexes over the Voyage summary embeddings.
    add_index :games, :summary_embedding,
              name: "index_games_on_summary_embedding_hnsw",
              using: :hnsw, opclass: :vector_cosine_ops
    add_index :videos, :summary_embedding,
              name: "index_videos_on_summary_embedding_hnsw",
              using: :hnsw, opclass: :vector_cosine_ops

    # Trigram GIN indexes for fuzzy title matching.
    add_index :games, :title,
              name: "index_games_on_title_trigram",
              using: :gin, opclass: :gin_trgm_ops
    add_index :videos, :title,
              name: "index_videos_on_title_trigram",
              using: :gin, opclass: :gin_trgm_ops
  end
end
