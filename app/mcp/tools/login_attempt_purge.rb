# Phase 25 — 01d. `login_attempt_purge` MCP tool.
#
# Bulk-deletes LoginAttempt rows by filter. Delegates to
# `Auth::AttemptPurger` (which enforces the safety rule: an empty
# filter is rejected — operators cannot accidentally wipe the entire
# attempt log).
#
# Two-step confirm pattern. `confirm: "no"` returns a preview that
# computes the prospective row count without performing the delete;
# `confirm: "yes"` runs the batched delete and audit-logs.
#
# Audit logging: the tool wraps the service call so the operator
# action is captured with `source_surface: :mcp` and metadata
# carrying the applied filter + the deleted row count. Q-K resolves
# to system-wide: any `auth`-scoped caller can purge any rows.
#
# Filter set (mirrors `Auth::AttemptPurger`):
#
#   - `result`       — enum string (success / failed / pending_approval / blocked / rate_limited)
#   - `since`        — ISO8601 ts; rows with `created_at >= since`
#   - `until_ts`     — ISO8601 ts; rows with `created_at <= until_ts`
#   - `ip`           — exact match on the row's ip
#   - `fingerprint`  — exact match on the row's fingerprint_hash
#   - `user_id`      — integer FK on the row's user_id
#
# Scope: `auth` (Phase 25 — LD-8).
module Mcp
  module Tools
    class LoginAttemptPurge < MCP::Tool
      tool_name "login_attempt_purge"
      description "bulk-delete login_attempts rows by filter. requires confirm: \"yes\" + at least one filter (empty filter is rejected)."

      input_schema(
        type: "object",
        properties: {
          result: {
            type: "string",
            description: "enum string filter (success / failed / pending_approval / blocked / rate_limited)."
          },
          since: {
            type: "string",
            description: "iso8601 timestamp; only rows created at or after this point are deleted."
          },
          until_ts: {
            type: "string",
            description: "iso8601 timestamp; only rows created at or before this point are deleted."
          },
          ip: {
            type: "string",
            description: "exact-match filter on the row's ip."
          },
          fingerprint: {
            type: "string",
            description: "exact-match filter on the full SHA256 fingerprint hash."
          },
          user_id: {
            type: "integer",
            description: "exact-match filter on the row's user_id."
          },
          confirm: {
            type: "string",
            enum: [ "yes", "no" ],
            description: "if 'no' or absent, returns a preview count and deletes nothing. if 'yes', executes."
          }
        },
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true)

      FILTER_KEYS = %i[result since until_ts ip fingerprint user_id].freeze

      def self.call(result: nil, since: nil, until_ts: nil,
                    ip: nil, fingerprint: nil, user_id: nil,
                    confirm: "no", **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        unless YesNo.yes_no?(confirm)
          return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})",
                                code: "invalid_input")
        end

        filter = {
          result: result,
          since: since,
          until_ts: until_ts,
          ip: ip,
          fingerprint: fingerprint,
          user_id: user_id
        }.compact

        if filter.values.all? { |v| v.to_s.strip.empty? }
          return error_response("at least one filter is required (empty purge rejected).",
                                code: "invalid_input")
        end

        confirmed = YesNo.from_yes_no(confirm)

        unless confirmed
          return preview_response(filter)
        end

        acting = Current.user
        if acting.nil?
          return error_response("acting user missing", code: "invalid_input")
        end

        begin
          result_struct = Auth::AttemptPurger.call(
            filter: filter,
            acting_user: acting,
            source: :mcp
          )
        rescue Auth::AttemptPurger::EmptyFilter => e
          return error_response(e.message, code: "invalid_input")
        rescue Auth::AttemptPurger::InvalidFilter => e
          return error_response(e.message, code: "invalid_filter")
        rescue ArgumentError => e
          return error_response(e.message, code: "invalid_input")
        end

        # Audit-log the purge once outside the service transaction. The
        # `target` is the User who performed the purge (no per-row
        # target makes sense for a bulk delete); metadata carries the
        # applied filter + the resulting count.
        audit_log = Auth::AuditLogger.call(
          acting_user: acting,
          source_surface: :mcp,
          action: :purge,
          target_type: "User",
          target_id: acting.id,
          metadata: {
            "scope"         => "login_attempts",
            "filter"        => result_struct.filter,
            "deleted_count" => result_struct.deleted_count
          }
        )

        payload = {
          purged: "yes",
          deleted_count: result_struct.deleted_count,
          filter: result_struct.filter,
          audit_log_id: audit_log.id,
          result: "ok"
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      # Preview path: compute the prospective row count without
      # touching the table. Re-runs the same filter logic the service
      # would apply so the count is faithful.
      def self.preview_response(filter)
        prospective_count = nil
        prospective_error = nil
        begin
          prospective_count = preview_count(filter)
        rescue Auth::AttemptPurger::InvalidFilter => e
          prospective_error = e.message
        end

        if prospective_error
          return error_response(prospective_error, code: "invalid_filter")
        end

        payload = {
          preview: {
            filter: filter,
            prospective_deleted_count: prospective_count,
            side_effects: {
              will_delete_login_attempt_rows: prospective_count.to_i > 0 ? "yes" : "no",
              will_audit_log:                 prospective_count.to_i > 0 ? "yes" : "no"
            },
            warning: "Hard delete; rows cannot be restored."
          },
          next_step: "Resubmit with confirm: \"yes\" to perform the purge."
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      # Mirror Auth::AttemptPurger's filter narrowing without
      # performing a delete. We re-apply the same precedence rules so
      # the count matches what would land.
      def self.preview_count(filter)
        scope = LoginAttempt.all

        if (v = filter[:result].to_s.presence) && LoginAttempt.results.key?(v)
          scope = scope.where(result: LoginAttempt.results[v])
        end

        if (v = filter[:since].to_s.presence)
          ts = parse_ts!(v, key: :since)
          scope = scope.where(LoginAttempt.arel_table[:created_at].gteq(ts))
        end

        if (v = filter[:until_ts].to_s.presence)
          ts = parse_ts!(v, key: :until_ts)
          scope = scope.where(LoginAttempt.arel_table[:created_at].lteq(ts))
        end

        if (v = filter[:ip].to_s.presence)
          scope = scope.where(ip: v)
        end

        if (v = filter[:fingerprint].to_s.presence)
          scope = scope.where(fingerprint_hash: v)
        end

        if (v = filter[:user_id]).present?
          scope = scope.where(user_id: v.to_i)
        end

        scope.count
      end

      def self.parse_ts!(raw, key:)
        Time.iso8601(raw.to_s)
      rescue ArgumentError, TypeError
        raise Auth::AttemptPurger::InvalidFilter,
              "invalid #{key} timestamp (expected ISO8601)"
      end

      def self.error_response(msg, code: "error")
        payload = { error: code, message: msg }
        MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], error: true)
      end
    end
  end
end
