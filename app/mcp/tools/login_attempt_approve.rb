# Phase 25 — 01d. `login_attempt_approve` MCP tool.
#
# Approves a currently-pending login attempt: delegates to
# `Auth::LoginAttemptApprover` which promotes the linked session from
# `pending_approval` to `active`, upserts a TrustedLocation row, marks
# the linked notification read, and audit-logs the action.
#
# Two-step confirm pattern (CLAUDE.md hard rule for destructive /
# significant actions). `confirm: "no"` (default) returns a preview
# describing what would happen; `confirm: "yes"` executes.
#
# Scope: `auth` (Phase 25 — LD-8). The scope is opt-in per-token and
# strips on release (ADR 0004 precedent).
#
# Concurrency: the underlying service holds a pessimistic lock on the
# pending session for the duration of the transaction so concurrent
# approve + block calls cannot both succeed.
#
# Error contract (yes/no boundary preserved):
#
#   - missing `id` or `confirm`            → input validation error
#   - `confirm` not in {"yes", "no"}       → input validation error
#   - attempt not found                    → 404-shaped error
#   - attempt has no session_id            → already_resolved error
#   - session not in pending_approval      → already_resolved error
#   - session past approval_required_until → expired error
module Mcp
  module Tools
    class LoginAttemptApprove < MCP::Tool
      tool_name "login_attempt_approve"
      description "approve a pending login attempt. requires confirm: \"yes\" (two-step). returns the activated session id."

      input_schema(
        type: "object",
        properties: {
          id: {
            type: "integer",
            description: "LoginAttempt id of the pending attempt."
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

      def self.call(id: nil, confirm: "no", **_ignored)
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

        if !confirmed
          return preview_response(attempt)
        end

        acting = Current.user
        if acting.nil?
          return error_response("acting user missing", code: "invalid_input")
        end

        begin
          outcome = Auth::LoginAttemptApprover.call(
            login_attempt: attempt,
            acting_user: acting,
            source: :mcp,
            request: mcp_stub_request
          )
        rescue Auth::LoginAttemptApprover::PendingExpired => e
          return error_response(e.message, code: "expired")
        rescue Auth::LoginAttemptApprover::AlreadyResolved => e
          return error_response(e.message, code: "already_resolved")
        rescue ArgumentError => e
          return error_response(e.message, code: "invalid_input")
        end

        # Find the audit row written inside the service's transaction so
        # the caller can pivot to `auth_audit_log_list` if they want
        # more context. We look up by target + action for the most
        # recent row (the transaction is closed by the time we return).
        audit_log = AuthAuditLog
                      .for_target(attempt.class.name, attempt.id)
                      .where(action: AuthAuditLog.actions[:approve])
                      .order(created_at: :desc)
                      .first

        payload = {
          approved: "yes",
          attempt_id: attempt.id,
          session_id: outcome[:session].id,
          notification_id: outcome[:notification]&.id,
          audit_log_id: audit_log&.id,
          result: "ok"
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.preview_response(attempt)
        session = attempt.session
        payload = {
          preview: {
            attempt: attempt_summary(attempt),
            side_effects: {
              will_activate_session:        "yes",
              will_upsert_trusted_location: "yes",
              will_resolve_notification:    "yes"
            },
            warning: "This trusts the (fingerprint, ip prefix) pair for this user. Future logins from this pair skip the approval step."
          },
          next_step: "Resubmit with confirm: \"yes\" to approve.",
          can_proceed: can_proceed_yes_no(attempt, session)
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

      def self.can_proceed_yes_no(attempt, session)
        return "no" if session.nil?
        return "no" unless session.state_pending_approval?
        return "no" unless session.pending_within_window?
        "yes"
      end

      def self.error_response(msg, code: "error")
        payload = { error: code, message: msg }
        MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], error: true)
      end

      # MCP tools have no inbound `ActionDispatch::Request` — the call
      # came in over the JSON-RPC transport. The downstream
      # `Auth::SessionActivator` + `Auth::AttemptLogger` chain reads
      # `request.remote_ip` / `request.user_agent` / `request.params`
      # so we synthesize a minimal Rack env stamped with the
      # MCP-as-surface marker. The IP falls through to "0.0.0.0" by
      # design — there is no remote IP for a stdio MCP call. The audit
      # row's `source_surface: :mcp` is the canonical "this came from
      # MCP" record; the synthetic IP is filler.
      def self.mcp_stub_request
        ActionDispatch::Request.new(Rack::MockRequest.env_for(
          "/",
          "REMOTE_ADDR"      => "0.0.0.0",
          "HTTP_USER_AGENT"  => "pito-mcp/internal"
        ))
      end
    end
  end
end
