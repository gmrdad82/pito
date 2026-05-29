# frozen_string_literal: true

# Beta reboot baseline (P7 / T7.8).
#
# Single migration that rebuilds the schema from scratch against the
# locked 15-model audit at `docs/reboot/model-audit.md`. The dev DB
# was dropped in T0.8; this migration is intended to run once on an
# empty database (`bin/rails db:setup` per T7.9).
#
# Extensions covered here: pgcrypto, citext, vector, pg_trgm, unaccent.
# (P8 adds `tsvector` columns + GIN indexes on top of pg_trgm/unaccent.)
class BetaBaseline < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pgcrypto"
    enable_extension "citext"
    enable_extension "vector"
    enable_extension "pg_trgm"
    enable_extension "unaccent"

    # ── Auth / config ───────────────────────────────────────────────────

    create_table :youtube_connections do |t|
      t.string :google_subject_id, null: false
      t.string :email,             null: false
      t.text   :access_token,      null: false
      t.text   :refresh_token
      t.jsonb  :scopes,            null: false, default: []
      t.datetime :expires_at,        null: false
      t.datetime :last_authorized_at, null: false
      t.boolean  :needs_reauth,     null: false, default: false
      t.timestamps

      t.index :google_subject_id, unique: true
    end

    create_table :sessions do |t|
      t.string  :token_digest,  null: false
      t.integer :state,         null: false, default: 0
      t.datetime :revoked_at
      t.datetime :last_activity_at
      t.inet    :ip
      t.text    :user_agent
      t.string  :device
      t.string  :browser
      t.timestamps

      t.index :token_digest, unique: true
      t.index :state
    end

    create_table :totp_backup_codes do |t|
      t.string :code_digest, null: false
      t.datetime :used_at
      t.timestamps

      t.index :code_digest, unique: true
      t.index :used_at
    end

    create_table :app_settings do |t|
      t.string :key
      t.text   :value

      # Singleton-row TOTP state.
      t.text     :totp_seed_encrypted
      t.datetime :totp_enabled_at
      t.datetime :totp_disabled_at
      t.integer  :totp_last_used_step

      # Singleton-row pre-allocated API key columns (AR-encrypted).
      t.text :google_oauth_client_id
      t.text :google_oauth_client_secret
      t.text :voyage_api_key

      t.timestamps

      # Postgres allows multiple NULLs under a UNIQUE constraint, which
      # is what we want for the singleton + key/value mix.
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

      t.vector :summary_embedding, limit: 1024

      t.timestamps

      t.index :youtube_video_id, unique: true
      t.index :channel_id
      t.index :privacy_status
      t.index :publish_at,   where: "publish_at IS NOT NULL"
      t.index :published_at
      t.index :tags, using: :gin
      t.index :summary_embedding,
              name: "index_videos_on_summary_embedding_hnsw",
              using: :hnsw,
              opclass: :vector_cosine_ops
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
      t.string :igdb_checksum

      t.string :title, null: false, default: "Untitled game"
      t.text   :summary

      t.string :cover_image_id
      t.text   :platforms, array: true, null: false, default: []

      t.date    :release_date
      t.integer :release_year
      t.integer :release_precision

      # 3 ratings + counts.
      t.decimal :igdb_rating,             precision: 5, scale: 2
      t.integer :igdb_rating_count
      t.decimal :total_rating,            precision: 5, scale: 2
      t.integer :total_rating_count
      t.decimal :aggregated_rating,       precision: 5, scale: 2
      t.integer :aggregated_rating_count

      # 3 TTBs.
      t.integer :ttb_main_seconds
      t.integer :ttb_extras_seconds
      t.integer :ttb_completionist_seconds

      t.string :external_steam_app_id
      t.text   :alternative_names, array: true, null: false, default: []

      t.bigint :primary_genre_id

      t.datetime :igdb_synced_at

      t.date :played_at
      t.text :notes

      t.vector :summary_embedding, limit: 1024

      t.timestamps

      t.index :igdb_id,               unique: true, where: "igdb_id IS NOT NULL"
      t.index :igdb_slug,             unique: true, where: "igdb_slug IS NOT NULL"
      t.index :external_steam_app_id, where: "external_steam_app_id IS NOT NULL"
      t.index :primary_genre_id
      t.index :igdb_synced_at
      t.index :release_year
      t.index :alternative_names, using: :gin
      t.index :summary_embedding,
              name: "index_games_on_summary_embedding_hnsw",
              using: :hnsw,
              opclass: :vector_cosine_ops
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
      t.bigint :game_id

      t.string  :filename,   null: false
      t.string  :local_path, null: false

      t.integer :duration_seconds
      t.string  :resolution
      t.string  :aspect_ratio
      t.decimal :fps, precision: 6, scale: 3
      t.string  :codec

      t.integer :bit_depth, null: false, default: 8
      t.string  :color_profile

      t.integer :audio_track_count
      t.text    :audio_track_names, array: true, null: false, default: []

      t.boolean :has_commentary_track, null: false, default: false

      t.timestamps

      t.index :local_path, unique: true
      t.index :game_id
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

    add_foreign_key :footages, :games, on_delete: :nullify
  end
end
