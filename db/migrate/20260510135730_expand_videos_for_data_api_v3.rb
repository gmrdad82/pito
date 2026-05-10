# Phase 12 — video schema expansion + edit surface + pre-publish checklist.
#
# Reverses Phase 7 Path A2's literal full retract for `Video`. Brings back
# the YouTube Data API v3-modeled writable subset (title, description, tags,
# category_id, privacy_status, publish_at, ...), plus the four pre-publish
# checklist booleans + completion timestamp, plus a direct nullable
# `Video.project_id` foreign key (Timeline intermediary stays dropped per
# the realignment doc).
#
# Additive migration: every change is `add_column` / `add_index` /
# `add_reference` / `add_foreign_key` on the post-Phase-9 schema. The only
# rename is `playlist_items` → `playlist_videos` (terminology alignment
# with Note 1).
class ExpandVideosForDataApiV3 < ActiveRecord::Migration[8.1]
  def up
    # ───────────────────────────────────────────────────────────────────
    # videos — column additions (Data API v3 writable subset + pre-publish
    # checklist columns + project FK + last_sync_error + duration).
    # ───────────────────────────────────────────────────────────────────
    add_column :videos, :title,                          :string,   limit: 100, null: false, default: ""
    add_column :videos, :description,                    :text
    add_column :videos, :tags,                           :jsonb,    null: false, default: []
    add_column :videos, :category_id,                    :string
    add_column :videos, :thumbnail_url,                  :string
    add_column :videos, :privacy_status,                 :integer,  null: false, default: 0
    add_column :videos, :publish_at,                     :datetime
    add_column :videos, :published_at,                   :datetime
    add_column :videos, :self_declared_made_for_kids,    :boolean,  null: false, default: false
    add_column :videos, :made_for_kids_effective,        :boolean,  null: false, default: false
    add_column :videos, :contains_synthetic_media,       :boolean,  null: false, default: false
    add_column :videos, :etag,                           :string
    add_column :videos, :pre_publish_checked_at,         :datetime
    add_column :videos, :pre_publish_game_ok,            :boolean,  null: false, default: false
    add_column :videos, :pre_publish_age_ok,             :boolean,  null: false, default: false
    add_column :videos, :pre_publish_paid_promotion_ok,  :boolean,  null: false, default: false
    add_column :videos, :pre_publish_end_screen_ok,      :boolean,  null: false, default: false
    add_column :videos, :last_sync_error,                :text
    add_column :videos, :duration_seconds,               :integer

    # GIN index on the jsonb tags column so future "videos with tag X"
    # queries from the analytics phase are cheap.
    add_index :videos, :tags,           using: :gin
    add_index :videos, :privacy_status
    add_index :videos, :publish_at,     where: "publish_at IS NOT NULL"
    add_index :videos, :published_at

    # Direct nullable FK to projects. Replacement for the dropped Timeline
    # intermediary (realignment Resolved ambiguity #1). ON DELETE SET NULL
    # preserves Videos when their owning Project is deleted.
    add_reference :videos, :project, foreign_key: { on_delete: :nullify }, null: true, index: true

    # ───────────────────────────────────────────────────────────────────
    # `youtube_video_id` uniqueness — switch to case-sensitive (locked
    # decision Q12). YouTube IDs are case-sensitive on the URL side.
    # ───────────────────────────────────────────────────────────────────
    if index_exists?(:videos, :youtube_video_id, name: "index_videos_on_youtube_video_id")
      remove_index :videos, name: "index_videos_on_youtube_video_id"
    end
    add_index :videos, :youtube_video_id, unique: true, name: "index_videos_on_youtube_video_id"

    # ───────────────────────────────────────────────────────────────────
    # playlist_items → playlist_videos (locked decision #6). Note 1 calls
    # this join `playlist_videos`; rename for terminology alignment.
    # ───────────────────────────────────────────────────────────────────
    if table_exists?(:playlist_items) && !table_exists?(:playlist_videos)
      # Rails' rename_table on Postgres auto-renames indexes whose names
      # contain the old table name (the standard `index_<table>_on_<col>`
      # shape is auto-aligned).
      rename_table :playlist_items, :playlist_videos
    end
    # `(playlist_id, position)` index for ordered listing — additive even
    # if the rename was a no-op.
    unless index_exists?(:playlist_videos, [ :playlist_id, :position ])
      add_index :playlist_videos, [ :playlist_id, :position ]
    end
  end

  def down
    if index_exists?(:playlist_videos, [ :playlist_id, :position ])
      remove_index :playlist_videos, [ :playlist_id, :position ]
    end
    if table_exists?(:playlist_videos) && !table_exists?(:playlist_items)
      rename_table :playlist_videos, :playlist_items
    end

    if index_exists?(:videos, :youtube_video_id, name: "index_videos_on_youtube_video_id")
      remove_index :videos, name: "index_videos_on_youtube_video_id"
    end
    add_index :videos, :youtube_video_id, unique: true,
              name: "index_videos_on_youtube_video_id"

    remove_reference :videos, :project, foreign_key: true, index: true

    remove_index :videos, :published_at
    remove_index :videos, :publish_at
    remove_index :videos, :privacy_status
    remove_index :videos, :tags

    remove_column :videos, :duration_seconds
    remove_column :videos, :last_sync_error
    remove_column :videos, :pre_publish_end_screen_ok
    remove_column :videos, :pre_publish_paid_promotion_ok
    remove_column :videos, :pre_publish_age_ok
    remove_column :videos, :pre_publish_game_ok
    remove_column :videos, :pre_publish_checked_at
    remove_column :videos, :etag
    remove_column :videos, :contains_synthetic_media
    remove_column :videos, :made_for_kids_effective
    remove_column :videos, :self_declared_made_for_kids
    remove_column :videos, :published_at
    remove_column :videos, :publish_at
    remove_column :videos, :privacy_status
    remove_column :videos, :thumbnail_url
    remove_column :videos, :category_id
    remove_column :videos, :tags
    remove_column :videos, :description
    remove_column :videos, :title
  end
end
