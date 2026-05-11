# Phase 25 — 01a (LD-8). `login_attempts_list` MCP tool scaffold.
#
# This is the SCAFFOLD version: filter set is minimal (result, since,
# ip, fingerprint), pagination caps at 100 rows. Full tool surface +
# the dedicated `auth` scope wiring land in 01d. Until then, the
# scaffold requires the existing `app` scope so it can be exercised
# end-to-end from a default Claude-mobile token.
#
# Boundary contract:
#
#   - input booleans (none on this tool yet) ride the yes/no
#     convention; non-booleans pass through unchanged.
#   - output rows carry `"is_success"`, `"is_failed"`, `"is_blocked"`
#     yes/no strings per LD-15 so callers can branch without parsing
#     the enum.
#   - `fingerprint_hash` is returned full (the caller already has the
#     `auth` scope — 01d enforces); `fingerprint_short` is included
#     for symmetry with the web/show page.
module Mcp
  module Tools
    class LoginAttemptsList < MCP::Tool
      tool_name "login_attempts_list"
      description "list login attempts against this pito install. filter by result/since/ip/fingerprint. paginated."

      DEFAULT_PER_PAGE = 25
      MAX_PER_PAGE = 100

      input_schema(
        type: "object",
        properties: {
          result: {
            type: "string",
            description: "filter by result (success / failed / pending_approval / blocked / rate_limited)."
          },
          since: {
            type: "string",
            description: "iso8601 timestamp; only rows created at or after this point are returned."
          },
          ip: {
            type: "string",
            description: "exact-match filter on the row's ip."
          },
          fingerprint: {
            type: "string",
            description: "exact-match filter on the full SHA256 fingerprint hash."
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

      def self.call(result: nil, since: nil, ip: nil, fingerprint: nil,
                    page: 1, per_page: DEFAULT_PER_PAGE, **_ignored)
        # 01a uses the `app` scope as a placeholder; 01d swaps to the
        # dedicated `auth` scope.
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::APP)
        return scope_err if scope_err

        page     = [ page.to_i, 1 ].max
        per_page = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min

        scope = LoginAttempt.all

        if result.present? && LoginAttempt.results.key?(result.to_s)
          scope = scope.where(result: LoginAttempt.results[result.to_s])
        end

        if since.present?
          begin
            ts = Time.iso8601(since.to_s)
            scope = scope.since(ts)
          rescue ArgumentError
            # silently ignore — wider result set rather than tool error.
          end
        end

        if ip.present?
          scope = scope.for_ip(ip.to_s)
        end

        if fingerprint.present?
          scope = scope.for_fingerprint(fingerprint.to_s)
        end

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
        {
          id: attempt.id,
          created_at: attempt.created_at.utc.iso8601,
          result: attempt.result,
          reason: attempt.reason,
          is_success: attempt.result_success? ? "yes" : "no",
          is_failed:  attempt.result_failed?  ? "yes" : "no",
          is_blocked: attempt.result_blocked? ? "yes" : "no",
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
          email_attempted: attempt.email_attempted
        }
      end
    end
  end
end
