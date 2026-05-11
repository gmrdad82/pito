# Phase 25 — 01d. `login_attempt_unblock` MCP tool.
#
# Soft-unblocks a BlockedLocation row. Two callable shapes:
#
#   1. `blocked_location_id: <int>` — direct row id.
#   2. `fingerprint: <hash>, ip_prefix: <cidr>` — pair lookup; finds
#      the active matching row.
#
# Delegates to `Auth::BlockedLocationUnblocker`, which stamps
# `unblocked_at` + `unblocked_by_user_id` and audit-logs the action.
# Already-unblocked rows return as no-ops (idempotent — no fresh audit
# row).
#
# Two-step confirm pattern (CLAUDE.md hard rule). `confirm: "no"`
# returns a preview; `confirm: "yes"` executes.
#
# Scope: `auth` (Phase 25 — LD-8).
module Mcp
  module Tools
    class LoginAttemptUnblock < MCP::Tool
      tool_name "login_attempt_unblock"
      description "soft-unblock a (fingerprint, ip prefix) pair. supply either blocked_location_id OR (fingerprint + ip_prefix). requires confirm: \"yes\"."

      input_schema(
        type: "object",
        properties: {
          blocked_location_id: {
            type: "integer",
            description: "id of the BlockedLocation row to unblock."
          },
          fingerprint: {
            type: "string",
            description: "full SHA256 fingerprint hash; paired with ip_prefix."
          },
          ip_prefix: {
            type: "string",
            description: "CIDR ip prefix; paired with fingerprint."
          },
          confirm: {
            type: "string",
            enum: [ "yes", "no" ],
            description: "if 'no' or absent, returns a preview and creates no state. if 'yes', executes."
          }
        },
        additionalProperties: false
      )

      annotations(read_only_hint: false, destructive_hint: true)

      def self.call(blocked_location_id: nil, fingerprint: nil, ip_prefix: nil,
                    confirm: "no", **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        unless YesNo.yes_no?(confirm)
          return error_response("confirm must be 'yes' or 'no' (got #{confirm.inspect})",
                                code: "invalid_input")
        end

        if blocked_location_id.blank? && (fingerprint.blank? || ip_prefix.blank?)
          return error_response(
            "supply blocked_location_id OR (fingerprint + ip_prefix).",
            code: "invalid_input"
          )
        end

        # Resolve the target row up-front so we can build a preview
        # (with `confirm: "no"`) AND so we surface 404 before the
        # confirmation cycle.
        row = lookup_row(blocked_location_id: blocked_location_id,
                        fingerprint: fingerprint,
                        ip_prefix: ip_prefix)

        if row.nil?
          return error_response(
            "no matching blocked_location row found.",
            code: "not_found"
          )
        end

        confirmed = YesNo.from_yes_no(confirm)
        return preview_response(row) unless confirmed

        acting = Current.user
        if acting.nil?
          return error_response("acting user missing", code: "invalid_input")
        end

        begin
          outcome = Auth::BlockedLocationUnblocker.call(
            blocked_location: row,
            acting_user: acting,
            source: :mcp
          )
        rescue Auth::BlockedLocationUnblocker::NotBlocked => e
          return error_response(e.message, code: "not_found")
        rescue ArgumentError => e
          return error_response(e.message, code: "invalid_input")
        end

        audit_log = AuthAuditLog
                      .for_target("BlockedLocation", outcome[:blocked_location].id)
                      .where(action: AuthAuditLog.actions[:unblock])
                      .order(created_at: :desc)
                      .first

        payload = {
          unblocked: outcome[:already_unblocked] ? "no" : "yes",
          already_unblocked: outcome[:already_unblocked] ? "yes" : "no",
          blocked_location_id: outcome[:blocked_location].id,
          audit_log_id: audit_log&.id,
          result: "ok"
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      # Active-row preference when the pair is supplied. If only a
      # `blocked_location_id` is given, accept whatever row matches
      # regardless of active/inactive state — the service handles the
      # already-unblocked idempotent path.
      def self.lookup_row(blocked_location_id:, fingerprint:, ip_prefix:)
        if blocked_location_id.present?
          BlockedLocation.find_by(id: blocked_location_id)
        else
          BlockedLocation.active.for_pair(fingerprint, ip_prefix).first
        end
      end

      def self.preview_response(row)
        payload = {
          preview: {
            blocked_location: row_summary(row),
            side_effects: {
              will_stamp_unblocked_at: row.unblocked_at.nil? ? "yes" : "no",
              will_audit_log:          row.unblocked_at.nil? ? "yes" : "no"
            },
            already_unblocked: row.unblocked_at.nil? ? "no" : "yes",
            warning: "Subsequent attempts from this (fingerprint, ip prefix) pair will no longer be auto-blocked."
          },
          next_step: "Resubmit with confirm: \"yes\" to perform the unblock."
        }
        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.row_summary(row)
        {
          id: row.id,
          blocked_at: row.blocked_at&.utc&.iso8601,
          unblocked_at: row.unblocked_at&.utc&.iso8601,
          source_surface: row.source_surface,
          blocked_by_user_id: row.blocked_by_user_id,
          unblocked_by_user_id: row.unblocked_by_user_id,
          fingerprint_hash: row.fingerprint_hash,
          fingerprint_short: row.fingerprint_hash.to_s[0, 12],
          ip_prefix: row.ip_prefix,
          attempt_count: row.attempt_count.to_i,
          reason: row.reason
        }
      end

      def self.error_response(msg, code: "error")
        payload = { error: code, message: msg }
        MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], error: true)
      end
    end
  end
end
