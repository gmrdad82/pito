class AddTenantIdToVideoStats < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 1 of 3 for video_stats.

  def up
    add_reference :video_stats, :tenant, null: true, foreign_key: true, index: true
  end

  def down
    remove_reference :video_stats, :tenant, foreign_key: true
  end
end
