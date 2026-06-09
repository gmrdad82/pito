# frozen_string_literal: true

# Phase 2 (videos plan) — slim the Video model.
#
# `comment_count` / `like_count` come from the YouTube Data API
# (`videos.list?part=statistics`), so they belong on the polymorphic `stats`
# table next to `views` (P4) rather than on the row. Backfill them into `stats`
# (kinds `comments` / `likes`), then drop those columns plus the unused `etag`.
#
# Reversible: `down` re-adds the columns and restores the counts from `stats`.
class SlimVideosMigrateCountsToStats < ActiveRecord::Migration[8.1]
  def up
    # Backfill BEFORE dropping the columns — values move into `stats`.
    backfill_stat("comments", "comment_count")
    backfill_stat("likes", "like_count")

    remove_column :videos, :comment_count
    remove_column :videos, :like_count
    remove_column :videos, :etag
  end

  def down
    add_column :videos, :comment_count, :bigint, default: 0, null: false
    add_column :videos, :like_count, :bigint, default: 0, null: false
    add_column :videos, :etag, :string

    restore_column("comment_count", "comments")
    restore_column("like_count", "likes")
  end

  private

  def backfill_stat(kind, column)
    execute(<<~SQL.squish)
      INSERT INTO stats (entity_type, entity_id, kind, value, synced_at, created_at, updated_at)
      SELECT 'Video', id, #{connection.quote(kind)}, #{column}, NOW(), NOW(), NOW()
      FROM videos
      ON CONFLICT (entity_type, entity_id, kind)
      DO UPDATE SET value = EXCLUDED.value, synced_at = NOW(), updated_at = NOW()
    SQL
  end

  def restore_column(column, kind)
    execute(<<~SQL.squish)
      UPDATE videos
      SET #{column} = COALESCE(stats.value, 0)
      FROM stats
      WHERE stats.entity_type = 'Video'
        AND stats.entity_id = videos.id
        AND stats.kind = #{connection.quote(kind)}
    SQL
  end
end
