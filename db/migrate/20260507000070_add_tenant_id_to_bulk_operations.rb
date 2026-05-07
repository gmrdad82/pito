class AddTenantIdToBulkOperations < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 1 of 3 for bulk_operations.

  def up
    add_reference :bulk_operations, :tenant, null: true, foreign_key: true, index: true
  end

  def down
    remove_reference :bulk_operations, :tenant, foreign_key: true
  end
end
