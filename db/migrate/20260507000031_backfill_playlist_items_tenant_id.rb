class BackfillPlaylistItemsTenantId < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 2 of 3 for playlist_items. Backfill from
  # the parent playlist (which is already tenanted by the previous
  # migration in this batch).

  def up
    execute(<<~SQL.squish)
      UPDATE playlist_items
      SET tenant_id = playlists.tenant_id
      FROM playlists
      WHERE playlist_items.playlist_id = playlists.id
        AND playlist_items.tenant_id IS NULL
    SQL
  end

  def down
    execute("UPDATE playlist_items SET tenant_id = NULL")
  end
end
