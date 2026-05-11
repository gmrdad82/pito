# Phase 23 — Step 23a (Video Sync + Diff Dialog).
#
# Append-only audit table. Records every applied field change from a
# resolved `VideoDiff`. Mirrors `channel_change_logs` shape from
# Phase 7.5 §11a — same enforcement (read-only at the model layer;
# `update` / `destroy` raise `ActiveRecord::ReadOnlyRecord`).
#
# `source` records the direction of the apply:
#   - `pito_apply`   — Pito-wins; the value was pushed to YouTube.
#   - `youtube_pull` — YouTube-wins; the local column was overwritten.
#   - `initial_sync` — reserved for the first-time-sync path (Phase 22).
#
# No `tenant_id` per ADR 0003.
class CreateVideoChangeLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :video_change_logs do |t|
      t.bigint :video_id, null: false
      # Model-layer validator enforces inclusion in
      # Video::DIFF_RESOLVABLE_FIELDS. No DB CHECK constraint.
      t.string :field, null: false
      # Stored as text because YouTube field values include
      # multi-line descriptions and tag-arrays serialized as JSON.
      t.text :old_value
      t.text :new_value
      # `source` is an integer-backed enum on the model. Stored as int
      # so values can shift order without a DB migration.
      t.integer :source, null: false
      t.datetime :changed_at, null: false
      t.bigint :changed_by_user_id

      t.timestamps
    end

    add_index :video_change_logs, :video_id
    add_index :video_change_logs, :changed_at
    add_index :video_change_logs, :changed_by_user_id

    add_foreign_key :video_change_logs, :videos,
                    column: :video_id,
                    on_delete: :cascade
    add_foreign_key :video_change_logs, :users,
                    column: :changed_by_user_id,
                    on_delete: :nullify
  end
end
