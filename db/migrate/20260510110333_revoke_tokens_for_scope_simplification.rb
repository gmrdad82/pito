# Phase 10 — MCP scope simplification (ADR 0004).
#
# Per ADR 0004, the scope catalog collapses from 9 to 2 entries.
# Existing tokens are revoked; users re-pair Claude Mobile + Web MCP
# after deploy.
#
# Concretely:
#   - Every active `ApiToken` row is soft-revoked (`revoked_at` set to
#     `Time.current`). Rows stay for audit parity.
#   - Every active `Doorkeeper::AccessToken` row is soft-revoked.
#   - Every active `Doorkeeper::AccessGrant` row is soft-revoked.
#   - Every `OauthApplication.scopes` whitelist string is rewritten
#     in-place using the Phase 10 mapping table (legacy scope names →
#     `dev` / `app`). Duplicates are collapsed; an application that
#     ends up with no surviving scope is set to `"app"` defensively.
#
# Rollback is NOT supported. The prior 9-scope catalog is gone from
# the code; `down` exists only for Rails bookkeeping.
class RevokeTokensForScopeSimplification < ActiveRecord::Migration[8.1]
  # Mapping from the legacy scope catalog to the Phase 10 `dev` / `app`
  # split. Sourced from ADR 0004's table.
  LEGACY_SCOPE_MAP = {
    "dev:read"       => "dev",
    "dev:write"      => "dev",
    "website:read"   => "dev",
    "website:write"  => "dev",
    "yt:read"        => "app",
    "yt:write"       => "app",
    "yt:destructive" => "app",
    "project:read"   => "app",
    "project:write"  => "app"
  }.freeze

  def up
    now = Time.current

    say_with_time "soft-revoke all active ApiToken rows" do
      ApiToken.where(revoked_at: nil).update_all(revoked_at: now)
    end

    if ActiveRecord::Base.connection.table_exists?(:oauth_access_tokens)
      say_with_time "soft-revoke all active Doorkeeper access tokens" do
        OauthAccessToken.where(revoked_at: nil).update_all(revoked_at: now)
      end
    end

    if ActiveRecord::Base.connection.table_exists?(:oauth_access_grants)
      say_with_time "soft-revoke all active Doorkeeper access grants" do
        OauthAccessGrant.where(revoked_at: nil).update_all(revoked_at: now)
      end
    end

    if ActiveRecord::Base.connection.table_exists?(:oauth_applications)
      say_with_time "rewrite OauthApplication.scopes from legacy catalog to dev/app" do
        OauthApplication.find_each do |application|
          new_scopes = rewrite_scopes(application.scopes)
          application.update_columns(scopes: new_scopes) if new_scopes != application.scopes.to_s
        end
      end
    end
  end

  def down
    # Rollback intentionally not supported. The prior 9-scope catalog
    # has been removed from the code; restoring scope strings would
    # leave references to constants that no longer exist.
    say "Rollback is not supported — Phase 10 collapses the scope catalog destructively."
  end

  private

  # Rewrites a Doorkeeper-style space-separated scope string from the
  # legacy 9-scope catalog to the Phase 10 dev/app catalog. Unknown
  # entries pass through (defensive — would only happen on hand-typed
  # applications) and are then dropped by the dedupe step. An empty
  # surviving set defaults to "app" to keep the application usable.
  def rewrite_scopes(raw)
    parts = raw.to_s.split(/\s+/).reject(&:empty?)
    mapped = parts.map { |s| LEGACY_SCOPE_MAP[s] || ([ "dev", "app" ].include?(s) ? s : nil) }
    mapped = mapped.compact.uniq
    mapped = [ "app" ] if mapped.empty?
    mapped.sort.join(" ")
  end
end
