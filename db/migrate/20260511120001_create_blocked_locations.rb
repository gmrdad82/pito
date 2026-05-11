# Phase 25 — 01a. Auto-block list. Schema-only here; the actual auto-
# block insertion happens in 01f, and the `block this attempt` flow ships
# in 01d. The 01a sub-spec uses the table only for lookups
# (`BlockedLocation.for_pair?`) so the schema must be in place from day
# one.
#
# `source_surface` records which surface created the block (web / tui /
# mcp). `unblocked_at` IS NULL means "currently blocked"; soft-unblock
# preserves the audit trail.
class CreateBlockedLocations < ActiveRecord::Migration[8.1]
  def change
    create_table :blocked_locations do |t|
      t.string :fingerprint_hash, null: false, limit: 64
      t.string :ip_prefix, null: false
      t.datetime :blocked_at, null: false
      t.bigint :blocked_by_user_id, null: false
      t.integer :source_surface, null: false, default: 0
      t.text :reason
      t.datetime :last_attempt_at
      t.integer :attempt_count, null: false, default: 0
      t.datetime :unblocked_at
      t.bigint :unblocked_by_user_id

      t.timestamps
    end

    add_index :blocked_locations, [ :fingerprint_hash, :ip_prefix ],
              unique: true,
              name: "index_blocked_locations_unique_pair"
    add_index :blocked_locations, :unblocked_at
    add_index :blocked_locations, :blocked_by_user_id

    add_foreign_key :blocked_locations, :users,
                    column: :blocked_by_user_id,
                    on_delete: :restrict
    add_foreign_key :blocked_locations, :users,
                    column: :unblocked_by_user_id,
                    on_delete: :nullify
  end
end
