class AddTenantIdToSavedViews < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 1 of 3 for saved_views.

  def up
    add_reference :saved_views, :tenant, null: true, foreign_key: true, index: true
  end

  def down
    remove_reference :saved_views, :tenant, foreign_key: true
  end
end
