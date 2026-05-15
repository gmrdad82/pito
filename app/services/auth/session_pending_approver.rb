# Phase 25 — 01b. Pending-approval session creator.
#
# Called from `Login::ChallengesController#create` when the user picks
# the `[ask for approval]` branch after a correct-password new-location
# login. Responsibilities:
#
#   1. Mint a Session row in `pending_approval` state with
#      `approval_required_until = now + 10 min` (Session::PENDING_APPROVAL_TTL).
#   2. Write a `LoginAttempt` row with `result: :pending_approval`,
#      `reason: :new_location_pending`, linking the freshly-minted
#      session via `session_id`.
#   3. Refuse to mint if the user already has too many active pending
#      rows (anti-spam guard — `MAX_ACTIVE_PENDING` defaults to 3).
#
# Notification creation lives in `01c` (`Notifications::Pipeline`).
# This service stops at the pending row + the attempt row so 01b can
# ship without the notification surface; 01c calls
# `Notifications::Pipeline.deliver(:login_pending_approval, attempt:)`
# after this service returns.
#
# Contract:
#
#     row = Auth::SessionPendingApprover.call(
#       user:,
#       request:,
#       fingerprint_hash:,
#       ip_prefix:,
#     )
#
# Returns the persisted `Session` row. Raises
# `Auth::SessionPendingApprover::TooManyPending` when the spam guard
# trips so the controller can render a generic failure.
module Auth
  class SessionPendingApprover
    # Anti-spam guard. The 4th pending session on a given user trips
    # this — the controller catches the exception and renders generic
    # "Login failed." (LD-14). Threshold locked in the spec.
    MAX_ACTIVE_PENDING = 3

    class TooManyPending < StandardError; end

    def self.call(user:, request:, fingerprint_hash:, ip_prefix:)
      raise ArgumentError, "user required" if user.nil?
      raise ArgumentError, "fingerprint_hash required" if fingerprint_hash.blank?
      raise ArgumentError, "ip_prefix required" if ip_prefix.blank?

      ip = request&.remote_ip.to_s.presence || "0.0.0.0"
      ua = request&.user_agent.to_s.first(1024).presence || ""

      session_row = nil
      attempt_row = nil

      # P25 follow-up — F5. Race-free anti-spam guard.
      #
      # The MAX_ACTIVE_PENDING check + the session INSERT must be
      # serialized per-user. Without serialization two concurrent
      # correct-password attempts both read N pending rows, both fall
      # under the cap, both insert → the cap is exceeded by 1
      # (LD-6 violation).
      #
      # `User.lock("FOR UPDATE").find(user.id)` takes a row-level
      # exclusive lock on the `users` row for the duration of the
      # transaction. Concurrent callers serialize on that lock; the
      # second one re-reads the pending count AFTER the first commits
      # and sees the freshly-inserted row, so it correctly raises
      # `TooManyPending`. The lock is automatically released when the
      # transaction commits or rolls back.
      ActiveRecord::Base.transaction do
        User.lock("FOR UPDATE").find(user.id)

        # Defensive count of currently-pending rows whose window is
        # still open. Expired rows are NOT counted — they were already
        # transitioned by the sweeper (or will be soon).
        active_pending = user.sessions.pending_within_window.count
        if active_pending >= MAX_ACTIVE_PENDING
          raise TooManyPending,
                "user #{user.id} has #{active_pending} active pending sessions (cap #{MAX_ACTIVE_PENDING})"
        end

        session_row, _plaintext = Session.create_pending!(
          user: user,
          ip: ip,
          user_agent: ua
        )

        attempt_row = Auth::AttemptLogger.call(
          request: request,
          result: :pending_approval,
          reason: :new_location_pending,
          user: user,
          username: user.username,
          session: session_row
        )
      end

      # Phase 25 — 01c. Fire the urgent notification on the trusted-
      # surfaces banner so the operator on another device sees the
      # pending approval immediately. The dispatch is deliberately
      # OUTSIDE the transaction — a notification-helper failure must
      # NOT roll back the pending session + attempt row (the holding
      # page still functions without the notification).
      dispatch_pending_notification(attempt_row)

      session_row
    end

    def self.dispatch_pending_notification(attempt_row)
      return if attempt_row.nil?
      return if attempt_row.id.blank?

      NotificationSource::LoginPendingApproval.report!(attempt: attempt_row)
    rescue StandardError => e
      Rails.logger.warn(
        "[Auth::SessionPendingApprover] notification dispatch failed: " \
        "#{e.class}: #{e.message}"
      )
      nil
    end
  end
end
