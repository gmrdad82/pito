# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — Doorkeeper application
# subclass.
#
# Phase 8 — tenant drop. The `tenant_id` column is gone; this model is
# now a thin Doorkeeper subclass with no extra scoping. Doorkeeper
# resolves applications by `client_id` from `/oauth/token`,
# `/oauth/authorize`, and `/oauth/revoke` — surfaces that run before
# any cookie session is in scope. Listing in
# `/settings/oauth_applications` simply uses `OauthApplication.all`
# now that the install scope is install-wide.
class OauthApplication < Doorkeeper::Application
  self.table_name = "oauth_applications"
end
