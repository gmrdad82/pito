class BackfillPlaylistsTenantId < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 2 of 3 for playlists. Backfill via channel.

  def up
    execute(<<~SQL.squish)
      UPDATE playlists
      SET tenant_id = channels.tenant_id
      FROM channels
      WHERE playlists.channel_id = channels.id
        AND playlists.tenant_id IS NULL
    SQL
  end

  def down
    execute("UPDATE playlists SET tenant_id = NULL")
  end
end
