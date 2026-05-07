class AddTenantIdToPlaylists < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 1 of 3 for playlists.

  def up
    add_reference :playlists, :tenant, null: true, foreign_key: true, index: true
  end

  def down
    remove_reference :playlists, :tenant, foreign_key: true
  end
end
