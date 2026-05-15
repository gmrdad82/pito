# Phase 25 — 01b. Sweeps pending-approval sessions whose 10-minute
# window has elapsed and transitions them to `expired`.
#
# Idempotent. Runs from `SessionPendingApprovalSweeperJob` every minute
# AND can be called ad-hoc from a console.
#
# For every row transitioned, writes a `LoginAttempt` row with
# `result: :failed`, `reason: :pending_expired`, linked to the session
# via `session_id`. This keeps the audit trail honest: the operator
# can see "this pending request expired" without reconstructing from
# timestamps.
#
# Returns the count of transitioned rows so the caller / cron job can
# log a one-line tally.
#
# Locked decisions applied:
#
#   - Q-G option 2: expired rows stay in the DB. State flips to
#     `expired`; they cannot be retroactively approved (the activator
#     refuses terminal rows).
#   - LD-1 enum: `pending_expired` is one of the pre-declared reasons
#     in 01a's enum so no schema work is needed.
module Auth
  class PendingSessionExpirer
    def self.call
      transitioned = 0

      Session.expired_pending.find_each do |session|
        # Re-check `expired_pending?` per row — `find_each` batches
        # the snapshot, and we want to be safe against a concurrent
        # mutation that already flipped the state. The cron sweeper's
        # job is idempotency; double-running is fine.
        next unless session.expired_pending?

        flipped = false

        ActiveRecord::Base.transaction do
          flipped = session.expire_if_overdue!

          if flipped
            LoginAttempt.create!(
              user: session.user,
              email_attempted: session.user&.username.to_s,
              result: :failed,
              reason: :pending_expired,
              ip: session.ip.presence || "0.0.0.0",
              ip_prefix: Pito::Auth::IpPrefix.call(session.ip.to_s.presence || "0.0.0.0"),
              user_agent: session.user_agent.to_s.first(1024).presence || "",
              fingerprint_hash: Digest::SHA256.hexdigest(
                "expired-pending|#{session.id}|#{session.created_at.to_i}"
              ),
              session: session
            )
          end
        end

        transitioned += 1 if flipped
      rescue StandardError => e
        Rails.logger.error(
          "[Auth::PendingSessionExpirer] session=#{session&.id} #{e.class}: #{e.message}"
        )
        # Don't re-raise — one bad row must not stop the sweep.
        next
      end

      transitioned
    end
  end
end
