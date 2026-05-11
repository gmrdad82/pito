# Phase 25 — 01g. Stale-session sweeper.
#
# Revokes long-idle active sessions so a forgotten cookie cannot grant
# access weeks after the user last touched the app. Mirrors the
# `Session::ACTIVITY_DEBOUNCE` debounce pattern in reverse: a session
# whose `last_activity_at` is older than `STALE_AFTER` has been idle
# long enough that the cookie almost certainly belongs to a closed
# browser, a stolen laptop, or a long-since-abandoned device.
#
# Schedule lives in `config/sidekiq_cron.yml`:
#
#     session_stale_sweeper:
#       cron: "*/15 * * * *"
#       class: SessionStaleSweeperJob
#
# Idempotent: rows transitioned out of `:active` (already revoked /
# expired) are skipped. Each transition stamps `revoked_at` and bumps
# state to `:revoked`. The cron cadence is 15 minutes — coarse enough
# to keep the cost trivial, fine enough that a freshly stale session
# closes within one quarter hour.
class SessionStaleSweeperJob < ApplicationJob
  queue_as :default

  # Sessions idle longer than this are swept. Mirrors the spec's
  # "session older than X" instruction; 30 days lines up with the
  # `Session::REMEMBER_ME_TTL` cookie window — a remember-me cookie
  # expires on the same horizon, so the server-side row should not
  # outlive it.
  STALE_AFTER = 30.days

  def perform
    cutoff = STALE_AFTER.ago

    # Two-bucket sweep:
    #   1. last_activity_at recorded, in the past beyond cutoff.
    #   2. last_activity_at NULL but created_at beyond cutoff —
    #      catches sessions that never recorded an activity stamp
    #      (e.g., one-tab logins that never re-requested anything).
    scope = Session.state_active.where(revoked_at: nil).where(
      "(last_activity_at IS NOT NULL AND last_activity_at < :cutoff) " \
        "OR (last_activity_at IS NULL AND created_at < :cutoff)",
      cutoff: cutoff
    )

    revoked = 0
    scope.find_each do |row|
      row.revoke!
      revoked += 1
    end

    if revoked.positive?
      Rails.logger.info(
        "[SessionStaleSweeperJob] revoked=#{revoked} stale_after=#{STALE_AFTER.inspect}"
      )
    end

    revoked
  end
end
