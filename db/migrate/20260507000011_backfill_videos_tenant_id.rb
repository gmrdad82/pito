class BackfillVideosTenantId < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 2 of 3 for videos. Backfill via the channel
  # association. Raw SQL instead of touching the model class so the
  # `BelongsToTenant` default scope (added in the same checkpoint as
  # the concern) does not interfere.

  def up
    execute(<<~SQL.squish)
      UPDATE videos
      SET tenant_id = channels.tenant_id
      FROM channels
      WHERE videos.channel_id = channels.id
        AND videos.tenant_id IS NULL
    SQL
  end

  def down
    execute("UPDATE videos SET tenant_id = NULL")
  end
end
