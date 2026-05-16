# 2026-05-16 (sessions revamp) — drop the `sessions.remember` column
# entirely.
#
# The "remember me on this device (30 days)" checkbox + the
# corresponding cookie-expiry plumbing are gone. The previous behaviour
# extended the session cookie's `expires` to 30 days when the box was
# ticked; without remember-me every session cookie is session-only (no
# `expires` attribute), so the column has nothing to drive.
#
# Rows live on without the column — there is no separate index on
# `remember`, and the bulk of the row carries its own audit value via
# `created_at` / `last_activity_at` / `revoked_at`. Reversible — re-add
# the boolean column at the previous default (`false`, NOT NULL) on
# rollback so a downgraded build can still write to it.
class DropSessionRememberColumn < ActiveRecord::Migration[8.1]
  def change
    remove_column :sessions, :remember, :boolean, default: false, null: false
  end
end
