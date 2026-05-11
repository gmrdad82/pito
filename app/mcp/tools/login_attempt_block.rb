# Phase 25 — 01d. `login_attempt_block` MCP tool.
#
# Blocks a currently-pending login attempt: delegates to
# `Auth::LoginAttemptBlocker` which upserts a BlockedLocation row for
# the (fingerprint, ip_prefix) pair, revokes the pending session,
# stamps a fresh `result: blocked` LoginAttempt row (reason:
# `blocked_from_mcp`), marks the linked notification read, and
# audit-logs the action.
#
# Two-step confirm pattern (CLAUDE.md hard rule for destructive /
# significant actions). `confirm: "no"` (default) returns a preview;
# `confirm: "yes"` executes.
#
# Scope: `auth` (Phase 25 — LD-8).
#
# Idempotency: blocking an attempt whose pair is already in the active
# blocklist re-uses the existing BlockedLocation row (no duplicate
# created via the model's unique partial index). The audit row still
# lands so the operator action is captured.
module Mcp
  module Tools
    class LoginAttemptBlock < MCP::Tool
      tool_name "login_attempt_block"
      description "block a pending login attempt + auto-add the (fingerprint, ip prefix) pair to the blocklist. requires confirm: \"yes\" (two-step)."

      input_schema(
        type: "object",
        properties: {
          id: {
            type: "integer",
            description: "LoginAttempt id of the pending attempt to block."
          },
          reason: {
            type: "string",
            description: "optional operator note attached to the BlockedLocation row."
          },
          confirm: {
            type: "string",
            enum: [ "yes", "no" ],
            description: "if 'no' or absent, returns a preview and creates no state. if 'yes', executes."
          }
        },
        required: [ "id" ],
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true)

      def self.call(id: nil, reason: nil, confirm: "no", **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        if id.nil?
          return error_response("id required", code: "invalid_input")
        end

        unless YesNo.yes_no?(confirm)
          return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})",
                                code: "invalid_input")
        end

        attempt = LoginAttempt.find_by(id: id)
        if attempt.nil?
          return error_response("login_attempt #{id} not found", code: "not_found")
        end

        confirmed = YesNo.from_yes_no(confirm)
        return preview_response(attempt) unless confirmed

        acting = Current.user
        if acting.nil?
          return error_response("acting user missing", code: "invalid_input")
        end

        begin
          outcome = Auth::LoginAttemptBlocker.call(
            login_attempt: attempt,
            acting_user: acting,
            source: :mcp,
            reason: reason
          )
        rescue Auth::LoginAttemptBlocker::PendingExpired => e
          return error_response(e.message, code: "expired")
        rescue Auth::LoginAttemptBlocker::AlreadyResolved => e
          return error_response(e.message, code: "already_resolved")
        rescue ArgumentError => e
          return error_response(e.message, code: "invalid_input")
        end

        audit_log = AuthAuditLog
                      .for_target(attempt.class.name, attempt.id)
                      .where(action: AuthAuditLog.actions[:block])
                      .order(created_at: :desc)
                      .first

        payload = {
          blocked: "yes",
          attempt_id: attempt.id,
          blocked_location_id: outcome[:blocked_location].id,
          revoked_session_id: outcome[:session].id,
          recorded_attempt_id: outcome[:attempt].id,
          notification_id: outcome[:notification]&.id,
          audit_log_id: audit_log&.id,
          result: "ok"
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.preview_response(attempt)
        session = attempt.session
        already_blocked = BlockedLocation.for_pair?(attempt.fingerprint_hash, attempt.ip_prefix)

        payload = {
          preview: {
            attempt: attempt_summary(attempt),
            side_effects: {
              will_create_blocked_location: already_blocked ? "no" : "yes",
              will_revoke_session:          "yes",
              will_resolve_notification:    "yes"
            },
            warning: "This blocks future attempts from this fingerprint + IP prefix.",
            already_blocked: already_blocked ? "yes" : "no"
          },
          next_step: "Resubmit with confirm: \"yes\" to perform the block.",
          can_proceed: can_proceed_yes_no(session)
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.attempt_summary(attempt)
        session = attempt.session
        {
          id: attempt.id,
          created_at: attempt.created_at.utc.iso8601,
          result: attempt.result,
          reason: attempt.reason,
          ip: attempt.ip.to_s,
          ip_prefix: attempt.ip_prefix,
          geo: {
            city: attempt.geo_city,
            region: attempt.geo_region,
            country: attempt.geo_country
          },
          browser: attempt.browser,
          os: attempt.os,
          fingerprint_short: attempt.fingerprint_short,
          fingerprint_hash: attempt.fingerprint_hash,
          email_attempted: attempt.email_attempted,
          user_id: attempt.user_id,
          session_id: attempt.session_id,
          session_state: session&.state,
          expires_at: session&.approval_required_until&.utc&.iso8601,
          is_expired: session && session.expired_pending? ? "yes" : "no"
        }
      end

      def self.can_proceed_yes_no(session)
        return "no" if session.nil?
        return "no" unless session.state_pending_approval?
        return "no" unless session.pending_within_window?
        "yes"
      end

      def self.error_response(msg, code: "error")
        payload = { error: code, message: msg }
        MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], error: true)
      end
    end
  end
end
