# Phase 25 — 01c (LD-13). Auth audit log table.
#
# Every approve / block (and, in later sub-specs, unblock / purge /
# totp_enroll / totp_disable / backup_code_regenerate) writes one row
# here via `Auth::AuditLogger`. Distinct from `LoginAttempt` — that
# table is per-attempt; this table is per-operator-action. Never
# auto-pruned.
#
# `source_surface` enum mirrors `BlockedLocation#source_surface`
# (web=0 / tui=1 / mcp=2). `action` is an integer enum encoding the
# full LD-13 action vocabulary so sub-specs 01d–01f need no further
# migration.
class CreateAuthAuditLogs < ActiveRecord::Migration[8.1]
  def change
    create_table :auth_audit_logs do |t|
      t.references :acting_user,
                   null: false,
                   foreign_key: { to_table: :users }
      t.integer :source_surface, null: false
      t.integer :action, null: false
      t.string :target_type, null: false
      t.bigint :target_id, null: false
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :auth_audit_logs, [ :target_type, :target_id ]
    add_index :auth_audit_logs, :created_at
    add_index :auth_audit_logs, :action
    add_index :auth_audit_logs, :source_surface
  end
end
