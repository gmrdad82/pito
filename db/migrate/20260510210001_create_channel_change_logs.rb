# Phase 7.5 — Step 11a (Channel Schema + Sync Foundation).
#
# Append-only audit table. Records every push of the rate-limited
# Channel fields (title / handle) so the management UI can show change
# history AND so the 14-day rate-limit gate has a reliable trail.
#
# No `tenant_id` per ADR 0003 (single-install + multi-user). Inserts
# only; the model raises on update / destroy via `readonly?`.
class CreateChannelChangeLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :channel_change_logs do |t|
      t.bigint :channel_id, null: false
      # Model-layer validator enforces inclusion in %w[title handle].
      # No DB CHECK constraint — keeps the migration portable and the
      # validator close to the surface the user sees errors on.
      t.string :field, null: false
      # Null for the first push when no prior value exists.
      t.string :old_value
      t.string :new_value, null: false
      t.datetime :changed_at, null: false
      t.bigint :changed_by_user_id, null: false

      t.timestamps
    end

    add_index :channel_change_logs, :channel_id
    add_index :channel_change_logs, :changed_at
    add_index :channel_change_logs, :changed_by_user_id

    add_foreign_key :channel_change_logs, :channels,
                    column: :channel_id,
                    on_delete: :cascade
    add_foreign_key :channel_change_logs, :users,
                    column: :changed_by_user_id,
                    on_delete: :restrict
  end
end
