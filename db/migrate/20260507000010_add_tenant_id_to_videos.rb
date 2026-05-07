class AddTenantIdToVideos < ActiveRecord::Migration[8.1]
  # Phase 5A §5.1 — step 1 of 3 for videos. Add the column nullable + FK,
  # index it. Steps 2 (backfill) and 3 (NOT NULL) are separate
  # migrations so rollback is cheap.

  def up
    add_reference :videos, :tenant, null: true, foreign_key: true, index: true
  end

  def down
    remove_reference :videos, :tenant, foreign_key: true
  end
end
