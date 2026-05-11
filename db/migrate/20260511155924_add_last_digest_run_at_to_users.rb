# Phase 26 — 01e. Daily digest scheduler.
#
# Per-user idempotency guard for the hourly `DailyDigestSchedulerJob`.
# Stamped to `Time.current` whenever the scheduler picks a user for a
# digest delivery; the scheduler re-running inside the same 24h window
# is a no-op because the picker requires
# `last_digest_run_at < (Time.current - 23.hours)`.
#
# UTC-stored, per the project-wide storage contract (Phase 26 01a).
#
# Default is the migration-time `Time.current` so existing users do not
# all double-fire on the first cron run after deploy — they look as if
# they "just received a digest" (which is the safe default; first real
# digest fires at the next user-local 09:00).
#
# NOT NULL: the scheduler always compares this column against
# `Time.current - 23.hours`; a NULL value would force a coalescing
# fallback in every query.
class AddLastDigestRunAtToUsers < ActiveRecord::Migration[8.1]
  def up
    # `default: -> { "CURRENT_TIMESTAMP" }` mirrors the column's lifecycle:
    # every freshly-inserted User row gets stamped to `now`, which is
    # exactly the "user looks as if they just received a digest" stance
    # we want — the next user-local 09:00 fires their first real digest.
    add_column :users, :last_digest_run_at, :datetime,
               default: -> { "CURRENT_TIMESTAMP" }
    # Belt-and-braces backfill for any existing rows that somehow
    # landed before the default took effect (shouldn't happen with
    # `add_column ... default:` but pg semantics vary across versions).
    execute "UPDATE users SET last_digest_run_at = CURRENT_TIMESTAMP WHERE last_digest_run_at IS NULL"
    change_column_null :users, :last_digest_run_at, false
    add_index :users, :last_digest_run_at
  end

  def down
    remove_index :users, :last_digest_run_at
    remove_column :users, :last_digest_run_at
  end
end
