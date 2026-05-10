# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — Doorkeeper
# authorization grant subclass.
#
# Phase 8 — tenant drop. The `tenant_id` column is gone; the
# `denormalize_tenant_from_application` callback is dropped. The grant
# is a thin Doorkeeper subclass with no extra scoping in the
# single-install world.
class OauthAccessGrant < Doorkeeper::AccessGrant
  self.table_name = "oauth_access_grants"
end
