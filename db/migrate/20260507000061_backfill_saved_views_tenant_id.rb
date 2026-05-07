class BackfillSavedViewsTenantId < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 2 of 3 for saved_views. SavedView has no
  # lineage column today; backfill to the seeded singleton tenant.

  def up
    execute(<<~SQL.squish)
      UPDATE saved_views
      SET tenant_id = (SELECT id FROM tenants ORDER BY id ASC LIMIT 1)
      WHERE tenant_id IS NULL
        AND EXISTS (SELECT 1 FROM tenants)
    SQL
  end

  def down
    execute("UPDATE saved_views SET tenant_id = NULL")
  end
end
