require "rails_helper"
require Rails.root.join("db/migrate/20260510110333_revoke_tokens_for_scope_simplification.rb")

# Phase 10 — MCP scope simplification (ADR 0004).
#
# Migration integration test. Drives the `up` body with fixture rows
# in the live test database and asserts the post-conditions:
#
#   - active ApiToken rows are soft-revoked
#   - active Doorkeeper access tokens are soft-revoked
#   - active Doorkeeper access grants are soft-revoked
#   - OauthApplication.scopes strings are rewritten using the legacy →
#     `dev`/`app` mapping
RSpec.describe RevokeTokensForScopeSimplification, type: :model do
  let!(:user) { User.first || create(:user) }
  let!(:application) { create(:oauth_application, scopes: "dev app") }

  # Build an ApiToken whose model validation would normally reject the
  # legacy scopes; we bypass it via `update_columns` after creating a
  # legitimate row. This simulates the pre-migration state where rows
  # carry legacy entries.
  def legacy_api_token(name)
    record, _ = ApiToken.generate!(
      user: user, name: name, scopes: [ Scopes::APP ]
    )
    record.update_columns(scopes: [ "dev:read", "yt:read" ])
    record
  end

  describe "#up" do
    it "soft-revokes active ApiToken rows" do
      record = legacy_api_token("api-token-1")
      expect(record.reload.revoked_at).to be_nil

      described_class.new.up

      expect(record.reload.revoked_at).to be_present
    end

    it "preserves the row (soft-revoke, not delete)" do
      record = legacy_api_token("api-token-2")
      expect { described_class.new.up }.not_to change { ApiToken.count }
      expect(record.reload).to be_revoked
    end

    it "soft-revokes active Doorkeeper access tokens" do
      token = OauthAccessToken.create!(
        application: application,
        resource_owner_id: user.id,
        scopes: "yt:read",
        expires_in: 7200
      )
      expect(token.revoked_at).to be_nil

      described_class.new.up

      expect(token.reload.revoked_at).to be_present
    end

    it "soft-revokes active Doorkeeper access grants" do
      grant = OauthAccessGrant.create!(
        application: application,
        resource_owner_id: user.id,
        token: SecureRandom.hex(20),
        expires_in: 600,
        redirect_uri: application.redirect_uri,
        scopes: "yt:read"
      )
      expect(grant.revoked_at).to be_nil

      described_class.new.up

      expect(grant.reload.revoked_at).to be_present
    end

    # Doorkeeper's `enforce_configured_scopes` validation rejects
    # legacy scope strings on save under the new catalog. Simulate the
    # pre-migration state by writing the column directly.
    def make_legacy_app(scopes_string)
      app = create(:oauth_application, scopes: "dev app")
      app.update_columns(scopes: scopes_string)
      app
    end

    it "rewrites OauthApplication.scopes from legacy strings to dev/app" do
      app = make_legacy_app("dev:read project:write yt:read")

      described_class.new.up

      expect(app.reload.scopes.to_s.split).to contain_exactly("dev", "app")
    end

    it "deduplicates the rewritten scopes set" do
      app = make_legacy_app("dev:read dev:write yt:read project:read")

      described_class.new.up

      expect(app.reload.scopes.to_s.split).to contain_exactly("dev", "app")
    end

    it "preserves an already-correct scopes string" do
      app = create(:oauth_application, scopes: "dev app")
      described_class.new.up
      expect(app.reload.scopes.to_s.split).to contain_exactly("dev", "app")
    end

    it "leaves an already-revoked ApiToken unchanged" do
      record, _ = ApiToken.generate!(
        user: user, name: "old-revoked", scopes: [ Scopes::APP ]
      )
      original = 2.days.ago
      record.update_columns(revoked_at: original)

      described_class.new.up

      expect(record.reload.revoked_at).to be_within(1.second).of(original)
    end
  end
end
