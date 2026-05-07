class BackfillBulkOperationItemsTenantId < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 2 of 3 for bulk_operation_items. Backfill
  # from the parent bulk_operation (already tenanted earlier in this
  # batch).

  def up
    execute(<<~SQL.squish)
      UPDATE bulk_operation_items
      SET tenant_id = bulk_operations.tenant_id
      FROM bulk_operations
      WHERE bulk_operation_items.bulk_operation_id = bulk_operations.id
        AND bulk_operation_items.tenant_id IS NULL
    SQL
  end

  def down
    execute("UPDATE bulk_operation_items SET tenant_id = NULL")
  end
end
