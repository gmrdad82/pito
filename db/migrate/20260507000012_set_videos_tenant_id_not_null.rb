class SetVideosTenantIdNotNull < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 3 of 3 for videos.

  def up
    change_column_null :videos, :tenant_id, false
  end

  def down
    change_column_null :videos, :tenant_id, true
  end
end
