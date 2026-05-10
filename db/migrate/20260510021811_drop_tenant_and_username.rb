# Phase 8 — Tenant Drop + Email-Only Login (ADR 0003).
#
# Destructive-and-reseed posture. Drops:
#
#   - the `tenant_id` column + foreign key on every domain table
#   - every index that started with `tenant_id` (single or composite)
#   - the `users.username` column and its unique index
#   - the `tenants` table itself (after every FK pointing at it has been
#     dropped)
#
# Where a composite index lost a useful "without tenant" shape, replaces
# it with the equivalent non-tenant index (Phase 8 spec, "Index
# replacements" section).
#
# **Rollback is explicitly NOT supported.** ADR 0003 locks
# destructive-and-reseed: pito has not shipped to anyone outside the
# developer's machine, no production data exists, and the canonical
# reset path is `bin/rails db:drop db:create db:migrate db:seed`. The
# `down` method below does the bare minimum required for Rails'
# migration bookkeeping (re-create the empty `tenants` table and the
# `users.username` column) — it does NOT restore prior data and does
# NOT reattach foreign-key constraints. Do not depend on it.
class DropTenantAndUsername < ActiveRecord::Migration[8.1]
  TENANTED_TABLES = %w[
    api_tokens
    bulk_operation_items
    bulk_operations
    channels
    collections
    footages
    games
    google_identities
    notes
    oauth_access_grants
    oauth_access_tokens
    oauth_applications
    playlist_items
    playlists
    project_references
    projects
    saved_views
    sessions
    timelines
    users
    video_stats
    video_uploads
    videos
    youtube_api_calls
  ].freeze

  def up
    # 1. Drop every foreign key pointing at `tenants` so the table can be
    #    dropped at the end. Rails infers the FK name; we go through
    #    `remove_foreign_key` table-by-table because some tables have
    #    multiple FKs and we only want the tenant one.
    TENANTED_TABLES.each do |table|
      if foreign_key_exists?(table.to_sym, :tenants)
        remove_foreign_key table.to_sym, :tenants
      end
    end

    # 2. Drop tenant-prefixed indexes that lose meaning once `tenant_id`
    #    is gone, and add replacements where the spec calls for them.
    drop_and_replace_indexes

    # 3. Drop `tenant_id` columns on every domain table.
    TENANTED_TABLES.each do |table|
      remove_column table.to_sym, :tenant_id if column_exists?(table.to_sym, :tenant_id)
    end

    # 4. Drop username from users (and its unique index).
    if index_exists?(:users, :username, name: "index_users_on_username")
      remove_index :users, name: "index_users_on_username"
    end
    remove_column :users, :username if column_exists?(:users, :username)

    # 5. Drop the tenants table itself.
    drop_table :tenants if table_exists?(:tenants)
  end

  def down
    # Bookkeeping only — does NOT restore prior data. ADR 0003
    # destructive-and-reseed: rollback is not supported. To reach the
    # pre-migration shape, restore from a backup or re-seed from
    # before-state credentials.
    create_table :tenants do |t|
      t.string :name, null: false
      t.citext :slug, null: false
      t.datetime :notes_syncing_at
      t.datetime :created_at, null: false
      t.datetime :updated_at, null: false
      t.index [ :slug ], name: "index_tenants_on_slug", unique: true
    end

    add_column :users, :username, :citext unless column_exists?(:users, :username)

    TENANTED_TABLES.each do |table|
      add_column(table.to_sym, :tenant_id, :bigint) unless column_exists?(table.to_sym, :tenant_id)
    end
  end

  private

  def drop_and_replace_indexes
    # channels
    safe_remove_index :channels, "index_channels_on_tenant_id_and_oauth_identity_id"
    safe_remove_index :channels, "index_channels_on_tenant_id_and_star"
    safe_remove_index :channels, "index_channels_on_tenant_id"

    # collections — replace tenant-prefixed name index with plain name index.
    safe_remove_index :collections, "index_collections_on_tenant_id_and_name"
    safe_remove_index :collections, "index_collections_on_tenant_id"
    add_index :collections, :name, name: "index_collections_on_name" \
      unless index_exists?(:collections, :name, name: "index_collections_on_name")

    # footages — replace `(tenant_id, local_path)` UNIQUE with `(local_path)` UNIQUE.
    safe_remove_index :footages, "index_footages_on_tenant_id_and_local_path"
    safe_remove_index :footages, "index_footages_on_tenant_id"
    add_index :footages, :local_path, unique: true, name: "index_footages_on_local_path" \
      unless index_exists?(:footages, :local_path, name: "index_footages_on_local_path")

    # games
    safe_remove_index :games, "index_games_on_tenant_id_and_title"
    safe_remove_index :games, "index_games_on_tenant_id"
    add_index :games, :title, name: "index_games_on_title" \
      unless index_exists?(:games, :title, name: "index_games_on_title")

    # google_identities — replace `(tenant_id, google_subject_id)` UNIQUE
    # with global UNIQUE on google_subject_id.
    safe_remove_index :google_identities, "index_google_identities_on_tenant_id_and_google_subject_id"
    safe_remove_index :google_identities, "index_google_identities_on_tenant_and_needs_reauth_partial"
    safe_remove_index :google_identities, "index_google_identities_on_tenant_id_and_user_id"
    safe_remove_index :google_identities, "index_google_identities_on_tenant_id"
    unless index_exists?(:google_identities, :google_subject_id, name: "index_google_identities_on_google_subject_id")
      add_index :google_identities, :google_subject_id, unique: true,
                name: "index_google_identities_on_google_subject_id"
    end

    # notes — replace `(tenant_id, path)` UNIQUE with `(project_id, path)` UNIQUE.
    safe_remove_index :notes, "index_notes_on_tenant_id_and_path"
    safe_remove_index :notes, "index_notes_on_tenant_id"
    unless index_exists?(:notes, [ :project_id, :path ], name: "index_notes_on_project_id_and_path")
      add_index :notes, [ :project_id, :path ], unique: true,
                name: "index_notes_on_project_id_and_path"
    end

    # projects
    safe_remove_index :projects, "index_projects_on_tenant_id_and_name"
    safe_remove_index :projects, "index_projects_on_tenant_id"
    add_index :projects, :name, name: "index_projects_on_name" \
      unless index_exists?(:projects, :name, name: "index_projects_on_name")

    # videos
    safe_remove_index :videos, "index_videos_on_tenant_channel_youtube_id"
    safe_remove_index :videos, "index_videos_on_tenant_id_and_star"
    safe_remove_index :videos, "index_videos_on_tenant_id"

    # youtube_api_calls — replace tenant-prefixed analytics composites
    # with their non-tenant equivalents to preserve query shapes.
    safe_remove_index :youtube_api_calls, "index_youtube_api_calls_on_tenant_kind_time"
    safe_remove_index :youtube_api_calls, "index_youtube_api_calls_on_tenant_identity_time"
    safe_remove_index :youtube_api_calls, "index_youtube_api_calls_on_tenant_outcome_time"
    safe_remove_index :youtube_api_calls, "index_youtube_api_calls_on_tenant_id"
    add_index :youtube_api_calls, [ :client_kind, :created_at ],
              name: "index_youtube_api_calls_on_kind_time" \
      unless index_exists?(:youtube_api_calls, [ :client_kind, :created_at ], name: "index_youtube_api_calls_on_kind_time")
    add_index :youtube_api_calls, [ :google_identity_id, :created_at ],
              name: "index_youtube_api_calls_on_identity_time" \
      unless index_exists?(:youtube_api_calls, [ :google_identity_id, :created_at ], name: "index_youtube_api_calls_on_identity_time")
    add_index :youtube_api_calls, [ :outcome, :created_at ],
              name: "index_youtube_api_calls_on_outcome_time" \
      unless index_exists?(:youtube_api_calls, [ :outcome, :created_at ], name: "index_youtube_api_calls_on_outcome_time")

    # Tables whose only tenant index is the single-column `(tenant_id)` —
    # drop without replacement.
    %w[
      api_tokens
      bulk_operation_items
      bulk_operations
      oauth_access_grants
      oauth_access_tokens
      oauth_applications
      playlist_items
      playlists
      project_references
      saved_views
      sessions
      timelines
      users
      video_stats
      video_uploads
    ].each do |table|
      safe_remove_index table.to_sym, "index_#{table}_on_tenant_id"
    end

    # sessions has a composite as well: `(tenant_id, user_id)` — drop it.
    safe_remove_index :sessions, "index_sessions_on_tenant_id_and_user_id"
  end

  def safe_remove_index(table, name)
    return unless index_name_exists?(table, name)
    remove_index table, name: name
  end
end
