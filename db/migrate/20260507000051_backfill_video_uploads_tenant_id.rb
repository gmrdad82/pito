class BackfillVideoUploadsTenantId < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 2 of 3 for video_uploads. Backfill from the
  # channel association (every upload belongs to a channel; videos
  # may be missing for in-progress uploads, so channel is the
  # reliable lineage column).

  def up
    execute(<<~SQL.squish)
      UPDATE video_uploads
      SET tenant_id = channels.tenant_id
      FROM channels
      WHERE video_uploads.channel_id = channels.id
        AND video_uploads.tenant_id IS NULL
    SQL
  end

  def down
    execute("UPDATE video_uploads SET tenant_id = NULL")
  end
end
