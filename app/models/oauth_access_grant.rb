# Phase 12 — Step B (6b-doorkeeper-oauth-server.md) — tenant-tagged
# Doorkeeper authorization grant (the short-lived `code` issued by
# `/oauth/authorize` and exchanged at `/oauth/token`).
#
# Implementation note: this model does NOT include `BelongsToTenant`.
# Doorkeeper looks up grants from `/oauth/token` (no cookie session
# in scope), and a default scope that raises on missing tenant context
# would break the flow. The denormalized `tenant_id` column is filled
# from the owning application — see `oauth_access_token.rb` for the
# matching note.
class OauthAccessGrant < Doorkeeper::AccessGrant
  self.table_name = "oauth_access_grants"

  belongs_to :tenant

  before_validation :denormalize_tenant_from_application

  private

  def denormalize_tenant_from_application
    return if tenant_id.present?
    return unless application

    self.tenant_id = application.tenant_id
  end
end
