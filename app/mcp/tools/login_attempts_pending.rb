# Phase 25 — 01b (LD-8) / 01d. `login_attempts_pending` MCP read tool.
#
# Returns rows whose attempt carries `result: pending_approval` AND
# whose linked session is still within its 10-minute approval window.
# Read-only.
#
# 01d swapped the scope gate from the temporary `app` placeholder to
# the dedicated `auth` scope (LD-8). The `auth` scope strips on
# release per ADR 0004 precedent.
#
# Boundary contract:
#
#   - Every Boolean serialises as `"yes"` / `"no"` (LD-15). Includes
#     `is_pending`, `is_expired`, and `has_session`.
#   - `fingerprint_hash` is returned full (the caller already holds
#     the `auth` scope when 01d ships); `fingerprint_short` mirrors
#     the web/show shape.
#   - `expires_at` is the linked session's `approval_required_until`,
#     ISO 8601, server-side authoritative.
module Mcp
  module Tools
    class LoginAttemptsPending < MCP::Tool
      tool_name "login_attempts_pending"
      description "list pending-approval login attempts. only rows currently within the 10-minute approval window are returned."

      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 50

      input_schema(
        type: "object",
        properties: {
          page: {
            type: "integer",
            description: "1-based page (default 1)."
          },
          per_page: {
            type: "integer",
            description: "results per page (default 25, max 50)."
          }
        },
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(page: 1, per_page: DEFAULT_PER_PAGE, **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        page     = [ page.to_i, 1 ].max
        per_page = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min

        # Currently-pending rows: result=pending_approval AND linked
        # session still in pending_approval AND approval_required_until
        # in the future. We join through `sessions` rather than relying
        # on the row's own `resolved_at` because the session is the
        # authoritative window.
        scope = LoginAttempt
          .pending
          .joins(:session)
          .where(sessions: { state: Session.states[:pending_approval] })
          .where("sessions.approval_required_until > ?", Time.current)

        total = scope.count
        rows = scope.recent.offset((page - 1) * per_page).limit(per_page)

        payload = {
          attempts: rows.map { |a| row_for(a) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total
          }
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.row_for(attempt)
        session = attempt.session
        {
          id: attempt.id,
          created_at: attempt.created_at.utc.iso8601,
          result: attempt.result,
          reason: attempt.reason,
          is_pending: attempt.result_pending_approval? ? "yes" : "no",
          is_expired: session && session.expired_pending? ? "yes" : "no",
          has_session: session.present? ? "yes" : "no",
          expires_at: session&.approval_required_until&.utc&.iso8601,
          ip: attempt.ip.to_s,
          ip_prefix: attempt.ip_prefix,
          geo: {
            city:    attempt.geo_city,
            region:  attempt.geo_region,
            country: attempt.geo_country
          },
          browser: attempt.browser,
          os: attempt.os,
          fingerprint_hash: attempt.fingerprint_hash,
          fingerprint_short: attempt.fingerprint_short,
          user_id: attempt.user_id,
          session_id: attempt.session_id,
          email_attempted: attempt.email_attempted
        }
      end
    end
  end
end
