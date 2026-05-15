# Phase 25 — 01e. `totp_status` MCP read tool.
#
# Returns the acting user's 2FA enrollment status — whether TOTP is on,
# when it was enabled, and how many backup codes remain. Enrollment /
# disable / regenerate are explicitly web-only this phase (the
# authenticator seed must reach the user's phone, which is not Claude);
# this tool is the only MCP surface that touches the TOTP state.
#
# Boundary contract (LD-15): every Boolean serialises as `"yes"` /
# `"no"`. The unused-code COUNT stays numeric — yes/no is for
# Booleans only per the project hard rule.
#
# Scope: `auth` (Phase 25 — LD-8). Strips on release per
# `Rails.application.config.x.mcp.expose_auth_scope`.
module Mcp
  module Tools
    class TotpStatus < MCP::Tool
      tool_name "totp_status"
      description "report 2FA enrollment status for the acting user (totp_enabled, enabled_at, unused backup codes)."

      input_schema(
        type: "object",
        properties: {},
        additionalProperties: false
      )

      annotations(read_only_hint: true)

      def self.call(**_ignored)
        scope_err = Mcp::ToolAuth.require_scope!(Scopes::AUTH)
        return scope_err if scope_err

        user = current_user
        if user.nil?
          payload = { error: "no_acting_user" }
          return MCP::Tool::Response.new(
            [ { type: "text", text: payload.to_json } ],
            error: true
          )
        end

        payload = {
          user_id: user.id,
          # Phase 29 — Unit A2. User auth refactor: `email` → `username`.
          # MCP surface is paused; this is the minimal column-gone fix.
          username: user.username,
          totp_enabled: user.totp_enabled? ? "yes" : "no",
          totp_enabled_at: user.totp_enabled_at&.utc&.iso8601,
          totp_disabled_at: user.totp_disabled_at&.utc&.iso8601,
          unused_backup_codes: user.totp_backup_codes.unused.count,
          used_backup_codes: user.totp_backup_codes.used.count
        }

        MCP::Tool::Response.new([ { type: "text", text: JSON.pretty_generate(payload) } ])
      end

      # The MCP server resolves the acting user off the bearer token's
      # owner. Tokens minted via `rails tokens:create` carry a `user`
      # association; OAuth-issued tokens carry `resource_owner_id`.
      def self.current_user
        token = Current.token
        return nil if token.nil?

        return token.user if token.respond_to?(:user) && token.user

        if token.respond_to?(:resource_owner_id) && token.resource_owner_id.present?
          return User.find_by(id: token.resource_owner_id)
        end

        nil
      end
    end
  end
end
