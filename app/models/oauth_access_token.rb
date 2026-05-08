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

  private

  def denormalize_tenant_from_application
    return if tenant_id.present?
    return unless application

    self.tenant_id = application.tenant_id
  end
end
