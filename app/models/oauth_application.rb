# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — tenant-tagged
# Doorkeeper application.
#
# Subclasses `Doorkeeper::Application` (selected via
# `application_class "OauthApplication"` in the Doorkeeper initializer)
# and adds a `tenant_id` column populated by the form on creation.
#
# Implementation note: this model does NOT include `BelongsToTenant`.
# Doorkeeper looks up applications by `client_id` from `/oauth/token`,
# `/oauth/authorize`, and `/oauth/revoke` — surfaces that run before
# any cookie session is in scope, where `Current.tenant` is not set.
# A default scope that raises on missing tenant would break OAuth.
# Tenant-aware listing in `/settings/oauth_applications` scopes
# explicitly via `where(tenant_id: Current.tenant_id)` instead.
class OauthApplication < Doorkeeper::Application
  self.table_name = "oauth_applications"

  belongs_to :tenant
  validates :tenant_id, presence: true
end
