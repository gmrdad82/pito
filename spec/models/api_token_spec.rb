require "rails_helper"

RSpec.describe ApiToken, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:token_digest) }
    it { is_expected.to validate_presence_of(:last_token_preview) }
    it { is_expected.to validate_presence_of(:scopes) }

    it "enforces unique token_digest" do
      digest = ApiToken.digest("test-token")
      create(:api_token, plaintext: "test-token")
      duplicate = build(:api_token, token_digest: digest)
      expect(duplicate).not_to be_valid
      expect(duplicate.errors[:token_digest]).to be_present
    end

    it "rejects scopes not in the catalog" do
      token = build(:api_token, scopes: [ "yt:read", "fake:scope" ])
      expect(token).not_to be_valid
      expect(token.errors[:scopes].first).to include("fake:scope")
    end

    it "rejects an empty scopes array" do
      token = build(:api_token, scopes: [])
      expect(token).not_to be_valid
      expect(token.errors[:scopes]).to be_present
    end
  end

  describe "associations" do
    it "belongs to a tenant and user" do
      token = create(:api_token)
      expect(token.tenant).to be_present
      expect(token.user).to be_present
    end
  end

  describe ".generate!" do
    let(:tenant) { create(:tenant) }
    let(:user)   { create(:user, tenant: tenant) }

    it "creates a token and returns plaintext exactly once" do
      record, plaintext = ApiToken.generate!(
        tenant: tenant,
        user: user,
        name: "test",
        scopes: [ Scopes::DEV_READ ]
      )

      expect(record).to be_persisted
      expect(record.name).to eq("test")
      expect(record.scopes).to eq([ Scopes::DEV_READ ])
      expect(record.tenant_id).to eq(tenant.id)
      expect(record.user_id).to eq(user.id)
      expect(record.last_token_preview).to eq(plaintext.last(4))
      expect(record.token_digest).to eq(ApiToken.digest(plaintext))
      expect(plaintext).to be_a(String)
      # The plaintext is ~43 chars (urlsafe_base64(32)).
      expect(plaintext.length).to be >= 40
    end

    it "accepts an optional expires_at" do
      future = 30.days.from_now
      record, _ = ApiToken.generate!(
        tenant: tenant, user: user,
        name: "expiring", scopes: [ Scopes::DEV_READ ],
        expires_at: future
      )
      expect(record.expires_at).to be_within(1.second).of(future)
    end
  end

  describe ".authenticate" do
    let(:tenant) { create(:tenant) }
    let(:user)   { create(:user, tenant: tenant) }

    it "returns the token for valid plaintext" do
      _record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "auth", scopes: [ Scopes::DEV_READ ]
      )

      result = ApiToken.authenticate(plaintext)
      expect(result).to be_present
      expect(result.name).to eq("auth")
    end

    it "updates last_used_at on success" do
      record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "usage", scopes: [ Scopes::DEV_READ ]
      )

      expect { ApiToken.authenticate(plaintext) }
        .to change { record.reload.last_used_at }.from(nil)
    end

    it "returns nil for invalid plaintext" do
      expect(ApiToken.authenticate("bogus")).to be_nil
    end

    it "returns nil for blank plaintext" do
      expect(ApiToken.authenticate("")).to be_nil
      expect(ApiToken.authenticate(nil)).to be_nil
    end

    it "returns nil for revoked token" do
      record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "revoked", scopes: [ Scopes::DEV_READ ]
      )
      record.revoke!

      expect(ApiToken.authenticate(plaintext)).to be_nil
    end

    it "returns nil for expired token" do
      record, plaintext = ApiToken.generate!(
        tenant: tenant, user: user, name: "expired", scopes: [ Scopes::DEV_READ ],
        expires_at: 1.hour.ago
      )
      expect(record.expired?).to be true

      expect(ApiToken.authenticate(plaintext)).to be_nil
    end
  end

  describe "#revoked? / #expired? / #usable?" do
    let(:tenant) { create(:tenant) }
    let(:user)   { create(:user, tenant: tenant) }

    it "is usable when neither revoked nor expired" do
      record, _ = ApiToken.generate!(tenant: tenant, user: user, name: "ok", scopes: [ Scopes::DEV_READ ])
      expect(record.revoked?).to be false
      expect(record.expired?).to be false
      expect(record.usable?).to be true
    end

    it "is not usable when revoked" do
      record, _ = ApiToken.generate!(tenant: tenant, user: user, name: "rv", scopes: [ Scopes::DEV_READ ])
      record.revoke!
      expect(record.revoked?).to be true
      expect(record.usable?).to be false
    end

    it "is not usable when expired" do
      record, _ = ApiToken.generate!(
        tenant: tenant, user: user, name: "ex", scopes: [ Scopes::DEV_READ ],
        expires_at: 5.minutes.ago
      )
      expect(record.expired?).to be true
      expect(record.usable?).to be false
    end
  end

  describe "#touch_used!" do
    it "updates last_used_at without firing validations or callbacks" do
      record = create(:api_token)
      expect(record.last_used_at).to be_nil

      record.touch_used!
      expect(record.reload.last_used_at).to be_present
    end
  end

  describe ".digest" do
    it "produces consistent digests" do
      expect(ApiToken.digest("hello")).to eq(ApiToken.digest("hello"))
    end

    it "produces different digests for different inputs" do
      expect(ApiToken.digest("hello")).not_to eq(ApiToken.digest("world"))
    end

    it "raises Api::AuthConfigurationMissing when the pepper credential is absent" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)
      expect { ApiToken.digest("anything") }.to raise_error(Api::AuthConfigurationMissing)
    end
  end
end
