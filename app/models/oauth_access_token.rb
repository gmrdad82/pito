# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — tenant-tagged
# Doorkeeper access token.
#
# Doorkeeper sets the parent class via `access_token_class
# "OauthAccessToken"` in the initializer. The `before_validation`
# callback denormalizes `tenant_id` from the owning `application`, so
# every issued access token inherits the tenant boundary.
#
# Implementation note: this model does NOT include `BelongsToTenant`.
# Doorkeeper's token endpoints (token / refresh / revoke) run without
# a cookie session — at that point `Current.tenant` is not set, and a
# default scope that raises on missing tenant context would break the
# OAuth flow. The denormalized `tenant_id` column is still authoritative
# for downstream tenant attribution; tenant scoping at the request
# level is enforced by `Sessions::AuthConcern` for cookie surfaces and
# (when adopted) by the bearer auth concern for API surfaces. See the
# accompanying `oauth_application.rb` for the BelongsToTenant-scoped
# parent record.
class OauthAccessToken < Doorkeeper::AccessToken
  self.table_name = "oauth_access_tokens"

  belongs_to :tenant

  before_validation :denormalize_tenant_from_application

  # Phase 7.5 — MCP OAuth bearer dispatch. The bearer auth path (both
  # `Api::AuthConcern` and `Mcp::RackApp`) sets `Current.user =
  # result.token.user`; `ApiToken` defines `belongs_to :user`, so we
  # mirror the read shape here. Doorkeeper stores the resource owner as
  # an opaque `resource_owner_id`; in Pito it is always a `User` row in
  # the same tenant as the access token (the `resource_owner_authenticator`
  # block in the Doorkeeper initializer pins `Current.user.id` at
  # consent time), so we resolve it back to a `User` for downstream
  # callers. Returns `nil` if the row was hard-deleted between consent
  # and bearer use; the bearer dispatch treats that as `invalid_token`.
  def user
    return nil unless resource_owner_id.present?

    User.find_by(id: resource_owner_id)
  end

  private

  def denormalize_tenant_from_application
    return if tenant_id.present?
    return unless application

    self.tenant_id = application.tenant_id
  end
end
