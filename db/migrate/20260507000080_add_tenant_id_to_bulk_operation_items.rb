class AddTenantIdToBulkOperationItems < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 1 of 3 for bulk_operation_items.

  def up
    add_reference :bulk_operation_items, :tenant, null: true, foreign_key: true, index: true
  end

  def down
    remove_reference :bulk_operation_items, :tenant, foreign_key: true
  end
end
