# Phase 25 — 01c. Blocker service for new-location pending logins.
#
# Sole entry point for the `[block the intruder]` action across web /
# TUI / MCP. Mirrors `Auth::LoginAttemptApprover`'s transaction +
# pessimistic-lock shape so concurrent approve + block requests are
# serialized by the database.
#
# Contract:
#
#     Auth::LoginAttemptBlocker.call(
#       login_attempt:,
#       acting_user:,
#       source: :web | :tui | :mcp,
#       reason: nil | String,
#     )
#
# Steps (all inside the transaction with a row-level lock on the
# pending session):
#
#   1. Find the pending session linked to the attempt (via `session_id`).
#   2. Upsert a `BlockedLocation` row for the
#      `(fingerprint_hash, ip_prefix)` pair (idempotent on the unique
#      partial index; an already-blocked pair returns the existing
#      row).
#   3. Revoke the pending session (flips state to `:revoked` + stamps
#      `revoked_at`).
#   4. Write a fresh `LoginAttempt` row with
#      `result: :blocked, reason: :blocked_from_<source>` so the audit
#      trail captures the operator action distinct from the
#      auto-block short-circuit row (`reason: :blocked_pair`).
#   5. Resolve the linked notification (mark read).
#   6. Audit-log via `Auth::AuditLogger`.
#
# Error contract:
#
#   - `Auth::LoginAttemptBlocker::PendingExpired` — pending row is past
#     its `approval_required_until` window AND has not been moved
#     out of `:pending_approval` yet (rare; the sweeper usually
#     handles this).
#   - `Auth::LoginAttemptBlocker::AlreadyResolved` — pending session
#     is no longer `:pending_approval` (approver / revoke beat us).
#   - `ArgumentError` — missing inputs.
#
# Defense-in-depth: only the caller-supplied `acting_user` is trusted.
# The service never reads request-supplied user-id params.
module Auth
  class LoginAttemptBlocker
    class PendingExpired < StandardError; end
    class AlreadyResolved < StandardError; end

    SOURCE_TO_REASON = {
      web: :blocked_from_web,
      tui: :blocked_from_tui,
      mcp: :blocked_from_mcp
    }.freeze

    def self.call(login_attempt:, acting_user:, source:, reason: nil, request: nil)
      raise ArgumentError, "login_attempt required" if login_attempt.nil?
      raise ArgumentError, "acting_user required" if acting_user.nil?

      source_sym = source.to_sym
      attempt_reason = SOURCE_TO_REASON[source_sym]
      raise ArgumentError, "invalid source: #{source.inspect}" if attempt_reason.nil?

      if login_attempt.session_id.blank?
        raise AlreadyResolved, "attempt has no session"
      end

      block_row = nil
      notification_row = nil
      revoked_session = nil
      block_attempt_row = nil

      ActiveRecord::Base.transaction do
        # Pessimistic lock on the session for the same reason as the
        # approver — serialize concurrent approve/block on the same
        # pending row.
        session = Session.lock.find_by(id: login_attempt.session_id)
        raise AlreadyResolved, "pending session is gone" if session.nil?

        unless session.state_pending_approval?
          raise AlreadyResolved,
                "pending session is in state #{session.state.inspect}"
        end

        unless session.pending_within_window?
          raise PendingExpired, "pending session window has elapsed"
        end

        # Upsert the blocked-pair row. We never duplicate on
        # `(fingerprint_hash, ip_prefix)` (DB unique partial index).
        block_row = BlockedLocation.active
                                   .for_pair(login_attempt.fingerprint_hash,
                                             login_attempt.ip_prefix)
                                   .first

        if block_row.nil?
          block_row = BlockedLocation.create!(
            fingerprint_hash: login_attempt.fingerprint_hash,
            ip_prefix: login_attempt.ip_prefix,
            blocked_at: Time.current,
            blocked_by_user: acting_user,
            source_surface: source_sym,
            reason: reason
          )
        end

        # Flip the session out of pending. `revoke!` stamps
        # `revoked_at` and bumps state to `:revoked` (terminal).
        session.revoke!
        revoked_session = session

        # Stamp a fresh attempt row carrying the operator-block reason
        # so the audit trail is unambiguous. We bypass
        # `Auth::AttemptLogger` here because the logger reads a real
        # request (we may not have one in TUI/MCP) AND would re-evaluate
        # the block list (causing it to relabel the row as
        # `:blocked_pair` instead of `:blocked_from_<source>`).
        block_attempt_row = LoginAttempt.create!(
          user: login_attempt.user,
          email_attempted: login_attempt.email_attempted,
          result: :blocked,
          reason: attempt_reason,
          ip: login_attempt.ip,
          ip_prefix: login_attempt.ip_prefix,
          geo_city: login_attempt.geo_city,
          geo_region: login_attempt.geo_region,
          geo_country: login_attempt.geo_country,
          user_agent: login_attempt.user_agent,
          browser: login_attempt.browser,
          os: login_attempt.os,
          fingerprint_hash: login_attempt.fingerprint_hash,
          session_id: session.id,
          approved_by_user_id: acting_user.id
        )

        notification_row = login_attempt.notification
        notification_row&.mark_read! if notification_row&.unread?

        Auth::AuditLogger.call(
          acting_user: acting_user,
          source_surface: source_sym,
          action: :block,
          target: login_attempt,
          metadata: {
            "blocked_location_id" => block_row.id,
            "session_id"          => session.id,
            "fingerprint_short"   => login_attempt.fingerprint_short,
            "ip_prefix"           => login_attempt.ip_prefix,
            "notification_id"     => notification_row&.id
          }
        )
      end

      {
        blocked_location: block_row,
        session: revoked_session,
        attempt: block_attempt_row,
        notification: notification_row
      }
    end
  end
end
