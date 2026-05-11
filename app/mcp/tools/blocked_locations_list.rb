# Phase 25 — 01f. `blocked_locations_list` MCP tool — paginated,
# filterable read of the auto-block list. Mirrors the shape of
# `Settings::Security::BlocksController#index` so a Claude session can
# audit the install's block list from any surface.
#
# Read-only. The destructive companions (`login_attempt_block`,
# `login_attempt_unblock`, `login_attempt_purge`, plus a future
# `blocked_location_purge`) land in 01d with the `auth` scope. Until
# `auth` ships this tool uses the existing `app` scope, the same
# precedent `login_attempts_list` follows in 01a/01b.
#
# Boundary contract (LD-15):
#
#   - `active` filter accepts `"yes"` / `"no"` strings; anything else
#     is treated as "both".
#   - Output rows carry `"is_active": "yes"|"no"` so callers can
#     branch without consulting `unblocked_at`.
#   - `fingerprint_short` mirrors the web row truncation (12 hex).
module Mcp
  module Tools
    class BlockedLocationsList < MCP::Tool
      tool_name "blocked_locations_list"
      description "list auto-blocked (fingerprint, ip prefix) pairs. filter by source/active/since/until/fingerprint/ip_prefix/blocked_by_user_id. paginated."

      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      input_schema(
        type: "object",
        properties: {
          source_surface: {
            type: "string",
            description: "filter by source surface (web / tui / mcp)."
          },
          blocked_by_user_id: {
            type: "integer",
            description: "filter by acting user id."
          },
          since: {
            type: "string",
            description: "iso8601 timestamp; only rows blocked at or after this point."
          },
          until_ts: {
            type: "string",
            description: "iso8601 timestamp; only rows blocked at or before this point."
          },
          fingerprint: {
            type: "string",
            description: "exact-match filter on the full SHA256 fingerprint hash."
          },
          ip_prefix: {
            type: "string",
            description: "exact-match filter on the CIDR ip prefix."
          },
          active: {
            type: "string",
            description: "yes | no; restrict to active or soft-unblocked rows (default both)."
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

      def self.call(source_surface: nil, blocked_by_user_id: nil,
                    since: nil, until_ts: nil,
                    fingerprint: nil, ip_prefix: nil,
                    active: nil,
                    page: 1, per_page: DEFAULT_PER_PAGE, **_ignored)
        # 01d swapped from the `app` placeholder to the dedicated
        # `auth` scope per LD-8. Mirrors `Mcp::Tools::LoginAttemptsList`.
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        begin
          result = Auth::BlockedLocationLister.call(
            filters: {
              source_surface: source_surface,
              blocked_by_user_id: blocked_by_user_id,
              since: since,
              until_ts: until_ts,
              fingerprint: fingerprint,
              ip_prefix: ip_prefix,
              active: active
            },
            page: page,
            per_page: [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min
          )
        rescue Auth::BlockedLocationLister::InvalidFilter => e
          return error_response(e.message)
        end

        payload = {
          blocks: result.rows.map { |row| row_for(row) },
          pagination: {
            page: result.page,
            per_page: result.per_page,
            total: result.total
          },
          filters: result.filters
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      def self.row_for(row)
        {
          id: row.id,
          blocked_at: row.blocked_at.utc.iso8601,
          source_surface: row.source_surface,
          blocked_by_user_id: row.blocked_by_user_id,
          unblocked_at: row.unblocked_at&.utc&.iso8601,
          unblocked_by_user_id: row.unblocked_by_user_id,
          is_active: row.active? ? "yes" : "no",
          fingerprint_hash: row.fingerprint_hash,
          fingerprint_short: row.fingerprint_hash.to_s[0, 12],
          ip_prefix: row.ip_prefix,
          attempt_count: row.attempt_count.to_i,
          last_attempt_at: row.last_attempt_at&.utc&.iso8601,
          reason: row.reason
        }
      end

      def self.error_response(message)
        payload = { error: "invalid_filter", message: message }
        MCP::Tool::Response.new(
          [ { type: "text", text: payload.to_json } ],
          error: true
        )
      end
    end
  end
end
