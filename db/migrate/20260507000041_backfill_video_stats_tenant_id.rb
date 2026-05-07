class BackfillVideoStatsTenantId < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 2 of 3 for video_stats. Backfill from the
  # parent video (already tenanted earlier in this batch).

  def up
    execute(<<~SQL.squish)
      UPDATE video_stats
      SET tenant_id = videos.tenant_id
      FROM videos
      WHERE video_stats.video_id = videos.id
        AND video_stats.tenant_id IS NULL
    SQL
  end

  def down
    execute("UPDATE video_stats SET tenant_id = NULL")
  end
end
