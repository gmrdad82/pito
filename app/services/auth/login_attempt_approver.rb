# Phase 25 — 01c. Approver service for new-location pending logins.
#
# Sole entry point for the `[yeah, it's me]` action across web / TUI /
# MCP. Wraps the multi-row mutation in a transaction with a pessimistic
# lock on the pending session so concurrent approve + block calls
# cannot both win.
#
# Contract:
#
#     Auth::LoginAttemptApprover.call(
#       login_attempt:,
#       acting_user:,
#       source: :web | :tui | :mcp,
#       request: nil | ActionDispatch::Request,
#     )
#
# Steps (all inside the transaction with a row-level lock on the
# pending session):
#
#   1. Find the pending session linked to the attempt (via `session_id`).
#   2. Promote it to `:active` via `Auth::SessionActivator` with
#      `existing:` (rotates the token, stamps a fresh attempt row,
#      upserts the trusted location).
#   3. Resolve the linked notification (mark read; row stays around so
#      the operator can see "you approved this from <surface>").
#   4. Audit-log via `Auth::AuditLogger`.
#
# Error contract:
#
#   - `Auth::LoginAttemptApprover::PendingExpired` — pending row is
#     past its `approval_required_until` window.
#   - `Auth::LoginAttemptApprover::AlreadyResolved` — pending session
#     is no longer `:pending_approval` (someone blocked / expired /
#     revoked it first).
#   - `ArgumentError` — missing inputs.
#
# Defense-in-depth: the contract is strict — only the caller-supplied
# `acting_user` (typically `Current.user`) is trusted. The service
# never reads request-supplied user-id params.
module Auth
  class LoginAttemptApprover
    class PendingExpired < StandardError; end
    class AlreadyResolved < StandardError; end

    SOURCE_TO_REASON = {
      web: :approved_from_web,
      tui: :approved_from_tui,
      mcp: :approved_from_mcp
    }.freeze

    def self.call(login_attempt:, acting_user:, source:, request: nil)
      raise ArgumentError, "login_attempt required" if login_attempt.nil?
      raise ArgumentError, "acting_user required" if acting_user.nil?

      source_sym = source.to_sym
      reason = SOURCE_TO_REASON[source_sym]
      raise ArgumentError, "invalid source: #{source.inspect}" if reason.nil?

      if login_attempt.session_id.blank?
        raise AlreadyResolved, "attempt has no session"
      end

      activated_session = nil
      notification_row = nil

      ActiveRecord::Base.transaction do
        # Pessimistic lock so concurrent approve + block calls cannot
        # both succeed. The lock is on the *session* (the resource
        # being transitioned), not on the attempt — multiple attempts
        # can point at the same session and we want the lock to
        # serialize state changes on the session, not on a particular
        # attempt row.
        session = Session.lock.find_by(id: login_attempt.session_id)
        raise AlreadyResolved, "pending session is gone" if session.nil?

        unless session.state_pending_approval?
          raise AlreadyResolved,
                "pending session is in state #{session.state.inspect}"
        end

        unless session.pending_within_window?
          raise PendingExpired, "pending session window has elapsed"
        end

        target_user = login_attempt.user
        raise AlreadyResolved, "attempt has no user" if target_user.nil?

        # Promote the pending session to active. The activator
        # rotates the token, stamps a fresh attempt row with
        # `reason: :approved_from_<source>`, and upserts the trusted
        # location. We pass the request (when available) so the
        # logger captures the *operator's* surface (web/tui/mcp) for
        # the audit trail's perspective; if no request is supplied
        # (TUI / MCP), the activator falls back to "0.0.0.0".
        activated_session, _plaintext = Auth::SessionActivator.call(
          user: target_user,
          request: request,
          fingerprint_hash: login_attempt.fingerprint_hash,
          ip_prefix: login_attempt.ip_prefix,
          reason: reason,
          existing: session
        )

        notification_row = login_attempt.notification
        notification_row&.mark_read! if notification_row&.unread?

        Auth::AuditLogger.call(
          acting_user: acting_user,
          source_surface: source_sym,
          action: :approve,
          target: login_attempt,
          metadata: {
            "session_id"        => session.id,
            "fingerprint_short" => login_attempt.fingerprint_short,
            "ip_prefix"         => login_attempt.ip_prefix,
            "notification_id"   => notification_row&.id
          }
        )
      end

      {
        session: activated_session,
        notification: notification_row
      }
    end
  end
end
