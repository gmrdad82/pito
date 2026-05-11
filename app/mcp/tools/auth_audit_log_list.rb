# Phase 25 — 01d. `auth_audit_log_list` MCP read tool.
#
# Paginated, filterable read of the AuthAuditLog. Lets a Claude
# session ask "what auth actions have happened on this install, when,
# from where, by whom" without leaving the MCP surface. Mirrors the
# shape of the future web audit-log view (01g).
#
# Read-only. Scope: `auth` (Phase 25 — LD-8). The scope strips on
# release per ADR 0004 precedent, so a production-installed MCP server
# does not advertise the tool at all.
#
# Filter set:
#
#   - `action`            — enum string (approve / block / unblock /
#                           purge / totp_enroll / totp_disable /
#                           backup_code_regenerate)
#   - `source_surface`    — enum string (web / tui / mcp)
#   - `since` / `until_ts`— ISO8601 timestamps brace `created_at`
#   - `acting_user_email` — exact-match join through the User
#                           association (typed citext under the hood)
#   - `target_type`       — exact-match polymorphic type
#   - `target_id`         — integer target id
#
# Boundary contract (LD-15): the response carries `is_recent: yes/no`
# on each row keyed off the last-7-day cutoff so a caller can tag the
# row without parsing the timestamp.
module Mcp
  module Tools
    class AuthAuditLogList < MCP::Tool
      tool_name "auth_audit_log_list"
      description "list auth audit log rows. filter by action/source_surface/since/until_ts/acting_user_email/target_type/target_id. paginated."

      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      input_schema(
        type: "object",
        properties: {
          action: {
            type: "string",
            description: "filter by action (approve / block / unblock / purge / totp_enroll / totp_disable / backup_code_regenerate)."
          },
          source_surface: {
            type: "string",
            description: "filter by source surface (web / tui / mcp)."
          },
          since: {
            type: "string",
            description: "iso8601 timestamp; only rows created at or after this point."
          },
          until_ts: {
            type: "string",
            description: "iso8601 timestamp; only rows created at or before this point."
          },
          acting_user_email: {
            type: "string",
            description: "exact-match filter on the acting user's email."
          },
          target_type: {
            type: "string",
            description: "exact-match polymorphic target_type (e.g. \"LoginAttempt\")."
          },
          target_id: {
            type: "integer",
            description: "exact-match polymorphic target_id."
          },
          page: {
            type: "integer",
            description: "1-based page (default 1)."
          },
          per_page: {
            type: "integer",
            description: "results per page (default 25, max 100)."
          }
        },
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(action: nil, source_surface: nil,
                    since: nil, until_ts: nil,
                    acting_user_email: nil,
                    target_type: nil, target_id: nil,
                    page: 1, per_page: DEFAULT_PER_PAGE, **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        page     = [ page.to_i, 1 ].max
        per_page = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min

        scope = AuthAuditLog.all

        if action.present?
          unless AuthAuditLog.actions.key?(action.to_s)
            return error_response("invalid action: #{action.inspect}")
          end
          scope = scope.where(action: AuthAuditLog.actions[action.to_s])
        end

        if source_surface.present?
          unless AuthAuditLog.source_surfaces.key?(source_surface.to_s)
            return error_response("invalid source_surface: #{source_surface.inspect}")
          end
          scope = scope.where(source_surface: AuthAuditLog.source_surfaces[source_surface.to_s])
        end

        if since.present?
          begin
            ts = Time.iso8601(since.to_s)
            scope = scope.where(AuthAuditLog.arel_table[:created_at].gteq(ts))
          rescue ArgumentError
            return error_response("invalid since timestamp (expected ISO8601): #{since.inspect}")
          end
        end

        if until_ts.present?
          begin
            ts = Time.iso8601(until_ts.to_s)
            scope = scope.where(AuthAuditLog.arel_table[:created_at].lteq(ts))
          rescue ArgumentError
            return error_response("invalid until_ts timestamp (expected ISO8601): #{until_ts.inspect}")
          end
        end

        if acting_user_email.present?
          user = User.find_by(email: acting_user_email.to_s)
          if user.nil?
            payload = empty_payload(page: page, per_page: per_page)
            return MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
          end
          scope = scope.where(acting_user_id: user.id)
        end

        if target_type.present?
          scope = scope.where(target_type: target_type.to_s)
        end

        if target_id.present?
          scope = scope.where(target_id: target_id.to_i)
        end

        total = scope.count
        rows = scope.recent.offset((page - 1) * per_page).limit(per_page)

        payload = {
          rows: rows.map { |r| row_for(r) },
          pagination: {
            page: page,
            per_page: per_page,
            total: total
          }
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.empty_payload(page:, per_page:)
        {
          rows: [],
          pagination: { page: page, per_page: per_page, total: 0 }
        }
      end

      def self.row_for(row)
        recent_cutoff = 7.days.ago
        {
          id: row.id,
          created_at: row.created_at.utc.iso8601,
          action: row.action,
          source_surface: row.source_surface,
          acting_user_id: row.acting_user_id,
          target_type: row.target_type,
          target_id: row.target_id,
          metadata: row.metadata,
          is_recent: row.created_at > recent_cutoff ? "yes" : "no"
        }
      end

      def self.error_response(msg)
        payload = { error: "invalid_filter", message: msg }
        MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], error: true)
      end
    end
  end
end
