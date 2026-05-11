# Phase 25 — 01b (LD-6). Adds the pending-approval state machine to
# the existing `sessions` table.
#
# Locked decisions applied:
#
#   - LD-6: `state` enum (active / pending_approval / expired / revoked)
#     default `active`; `approval_required_until` timestamp (10-minute
#     window) populated only on `pending_approval` rows.
#   - Q-G (resolved option 2): expired pending sessions stay as rows;
#     the column flips to `expired`. The audit trail survives. The
#     `approval_required_until` index lets the cron sweeper cheaply
#     find rows past expiry.
#
# Default 0 (= `active`) on the column keeps the existing rows valid
# without a backfill. The `NOT NULL` constraint is essential: nilling
# out the state would silently bypass the state machine.
class AddStateToSessions < ActiveRecord::Migration[8.1]
  def change
    add_column :sessions, :state, :integer, null: false, default: 0
    add_column :sessions, :approval_required_until, :datetime
    add_index :sessions, :state
    add_index :sessions, :approval_required_until
  end
end
