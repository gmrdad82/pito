# Phase 4 §3.7 — tenant-wide note-sync lock state. NoteSyncJob (Phase B)
# stamps `notes_syncing_at = Time.current` at start and clears it in `ensure`.
# The web layer treats the column as a 5-minute lock (stale-shield).
#
# Rollback recipe: `bin/rails db:rollback STEP=N` reaches this migration; the
# down side simply drops the column.
class AddNotesSyncingAtToTenants < ActiveRecord::Migration[8.1]
  def change
    add_column :tenants, :notes_syncing_at, :datetime
  end
end
