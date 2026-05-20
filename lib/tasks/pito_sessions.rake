# FB-132 (2026-05-21). Operator-only sessions maintenance tasks.
#
# `pito:sessions:backfill_device_browser` is the one-shot forward-fill
# that populates `sessions.device` + `sessions.browser` for rows that
# pre-date the schema change (migration
# `20260521002333_add_device_and_browser_to_sessions`). New rows are
# populated via the `before_validation :derive_device_and_browser`
# callback on `Session`; this rake task closes the gap for any rows
# already in the DB on migration time.
#
# Idempotent — re-running on already-populated rows is a no-op (the
# projection is deterministic and the `update_columns` overwrites with
# the same value). Skips revoked rows when invoked with `:active` so
# operators on installs with very large history can scope the backfill.

namespace :pito do
  namespace :sessions do
    desc "Backfill device + browser columns on existing sessions rows"
    task :backfill_device_browser, [ :scope ] => :environment do |_t, args|
      scope = args[:scope] || "all"
      relation =
        case scope
        when "active"  then Session.active_sessions
        else                Session.all
        end

      total = relation.count
      updated = 0
      relation.find_each do |s|
        s.update_columns(
          device: Formatting::UserAgent.device(s.user_agent.to_s),
          browser: Formatting::UserAgent.browser(s.user_agent.to_s)
        )
        updated += 1
      end

      puts "Backfilled #{updated} of #{total} sessions (scope=#{scope})."
    end
  end
end
