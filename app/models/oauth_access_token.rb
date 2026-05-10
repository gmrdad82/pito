# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — Doorkeeper access
# token subclass.
#
# Phase 8 — tenant drop. The `tenant_id` column is gone; the
# `denormalize_tenant_from_application` callback is dropped. The
# bearer dispatch (`Api::AuthConcern`, `Mcp::RackApp`) reads
# `resource_owner_id` directly to resolve the User; no tenant
# defense-in-depth is needed in a single-install world.
class OauthAccessToken < Doorkeeper::AccessToken
  self.table_name = "oauth_access_tokens"

  # Phase 7.5 — MCP OAuth bearer dispatch. The bearer auth path (both
  # `Api::AuthConcern` and `Mcp::RackApp`) sets `Current.user =
  # result.token.user`; `ApiToken` defines `belongs_to :user`, so we
  # mirror the read shape here. Doorkeeper stores the resource owner as
  # an opaque `resource_owner_id`; in Pito it is always a `User` row,
  # pinned at consent time by the `resource_owner_authenticator`
  # block in the Doorkeeper initializer. Returns `nil` if the row was
  # hard-deleted between consent and bearer use; the bearer dispatch
  # treats that as `invalid_token`.
  def user
    return nil unless resource_owner_id.present?

    User.find_by(id: resource_owner_id)
  end
end
