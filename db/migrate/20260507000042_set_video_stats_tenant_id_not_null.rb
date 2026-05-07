class SetVideoStatsTenantIdNotNull < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 3 of 3 for video_stats.

  def up
    change_column_null :video_stats, :tenant_id, false
  end

  def down
    change_column_null :video_stats, :tenant_id, true
  end
end
