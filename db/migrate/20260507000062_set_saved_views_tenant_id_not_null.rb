class SetSavedViewsTenantIdNotNull < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 3 of 3 for saved_views.

  def up
    change_column_null :saved_views, :tenant_id, false
  end

  def down
    change_column_null :saved_views, :tenant_id, true
  end
end
