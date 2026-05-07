class SetBulkOperationsTenantIdNotNull < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 3 of 3 for bulk_operations.

  def up
    change_column_null :bulk_operations, :tenant_id, false
  end

  def down
    change_column_null :bulk_operations, :tenant_id, true
  end
end
