# Phase 25 — 01a (LD-8) / 01d. `login_attempts_list` MCP tool.
#
# Filtered + paginated read of the LoginAttempt log. 01a shipped a
# minimal scaffold gated on the `app` scope; 01d expands the filter
# set (`until_ts`, `user_email`) and swaps the gate to the dedicated
# `auth` scope per LD-8. Strip-on-release follows the ADR 0004
# precedent.
#
# Boundary contract:
#
#   - input booleans (none on this tool) ride the yes/no convention.
#   - output rows carry `"is_success"`, `"is_failed"`, `"is_blocked"`
#     yes/no strings per LD-15 so callers can branch without parsing
#     the enum.
#   - `fingerprint_hash` is returned full because the caller already
#     holds the `auth` scope; `fingerprint_short` mirrors the web/show
#     page for symmetry.
#   - timestamps round-trip as ISO8601 UTC.
#
# Filter precedence: invalid filter values (e.g. unknown `result`,
# malformed timestamp) return a structured `invalid_filter` error
# rather than silently widening the result set. This matches
# `blocked_locations_list` and is stricter than the 01a scaffold by
# design — the dedicated scope is privileged so we surface caller
# mistakes loudly.
module Mcp
  module Tools
    class LoginAttemptsList < MCP::Tool
      tool_name "login_attempts_list"
      description "list login attempts against this pito install. filter by result/since/until_ts/ip/fingerprint/user_email. paginated."

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
          until_ts: {
            type: "string",
            description: "iso8601 timestamp; only rows created at or before this point are returned."
          },
          ip: {
            type: "string",
            description: "exact-match filter on the row's ip."
          },
          fingerprint: {
            type: "string",
            description: "exact-match filter on the full SHA256 fingerprint hash."
          },
          user_email: {
            type: "string",
            description: "exact-match filter on the attempt's email_attempted."
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

      def self.call(result: nil, since: nil, until_ts: nil,
                    ip: nil, fingerprint: nil, user_email: nil,
                    page: 1, per_page: DEFAULT_PER_PAGE, **_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        page     = [ page.to_i, 1 ].max
        per_page = [ [ per_page.to_i, 1 ].max, MAX_PER_PAGE ].min

        scope = LoginAttempt.all

        if result.present?
          unless LoginAttempt.results.key?(result.to_s)
            return error_response("invalid result: #{result.inspect}")
          end
          scope = scope.where(result: LoginAttempt.results[result.to_s])
        end

        if since.present?
          begin
            ts = Time.iso8601(since.to_s)
            scope = scope.since(ts)
          rescue ArgumentError
            return error_response("invalid since timestamp (expected ISO8601): #{since.inspect}")
          end
        end

        if until_ts.present?
          begin
            ts = Time.iso8601(until_ts.to_s)
            scope = scope.where(LoginAttempt.arel_table[:created_at].lteq(ts))
          rescue ArgumentError
            return error_response("invalid until_ts timestamp (expected ISO8601): #{until_ts.inspect}")
          end
        end

        if ip.present?
          scope = scope.for_ip(ip.to_s)
        end

        if fingerprint.present?
          scope = scope.for_fingerprint(fingerprint.to_s)
        end

        if user_email.present?
          scope = scope.where(email_attempted: user_email.to_s)
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

      def self.error_response(msg)
        payload = { error: "invalid_filter", message: msg }
        MCP::Tool::Response.new([ { type: "text", text: payload.to_json } ], error: true)
      end
    end
  end
end
