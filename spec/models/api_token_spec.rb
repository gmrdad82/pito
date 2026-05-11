require "rails_helper"

# Phase 8 — tenant drop. ApiToken belongs to a User install-wide; no
# tenant association.
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
      token = build(:api_token, scopes: [ "app", "fake:scope" ])
      expect(token).not_to be_valid
      expect(token.errors[:scopes].first).to include("fake:scope")
    end

    it "rejects an empty scopes array" do
      token = build(:api_token, scopes: [])
      expect(token).not_to be_valid
      expect(token.errors[:scopes]).to be_present
    end

    # Phase 10 — MCP scope simplification (ADR 0004). The 2-scope
    # catalog and the strip-on-release validation.
    describe "Phase 10 — 2-scope catalog" do
      it "accepts scopes: ['dev']" do
        expect(build(:api_token, scopes: [ Scopes::DEV ])).to be_valid
      end

      it "accepts scopes: ['app']" do
        expect(build(:api_token, scopes: [ Scopes::APP ])).to be_valid
      end

      it "accepts scopes: ['dev', 'app']" do
        expect(build(:api_token, scopes: [ Scopes::DEV, Scopes::APP ])).to be_valid
      end

      it "rejects scopes: ['foo'] (unknown)" do
        token = build(:api_token, scopes: [ "foo" ])
        expect(token).not_to be_valid
        expect(token.errors[:scopes].first).to include("foo")
      end

      it "rejects scopes: ['dev:read'] (legacy 9-scope string)" do
        token = build(:api_token, scopes: [ "dev:read" ])
        expect(token).not_to be_valid
        expect(token.errors[:scopes].first).to include("dev:read")
      end

      it "rejects scopes: ['yt:read'] (legacy 9-scope string)" do
        token = build(:api_token, scopes: [ "yt:read" ])
        expect(token).not_to be_valid
        expect(token.errors[:scopes].first).to include("yt:read")
      end

      it "accepts scopes: ['dev', 'dev'] (dedup is implicit at JSON storage)" do
        # The model accepts duplicate entries; the validation only
        # checks subset membership. Doorkeeper applications behave
        # the same way (their scope string is space-joined).
        expect(build(:api_token, scopes: [ Scopes::DEV, Scopes::DEV ])).to be_valid
      end
    end

    describe "Phase 10 — strip-on-release dev_scope_only_when_exposed validation" do
      around do |example|
        original = Rails.application.config.x.mcp.expose_dev_scope
        Rails.application.config.x.mcp.expose_dev_scope = false
        example.run
      ensure
        Rails.application.config.x.mcp.expose_dev_scope = original
      end

      it "rejects scopes: ['dev'] when expose_dev_scope is false" do
        # The catalog-subset check fires first because `Scopes::ALL`
        # is captured at boot. The dev_scope_only_when_exposed
        # validation guarantees rejection even if a runtime stub of
        # `Scopes::ALL` would otherwise let the row through.
        token = build(:api_token, scopes: [ Scopes::DEV ])
        expect(token).not_to be_valid
        expect(token.errors[:scopes].join).to match(/dev/)
      end

      it "rejects scopes: ['dev', 'app'] when expose_dev_scope is false" do
        token = build(:api_token, scopes: [ Scopes::DEV, Scopes::APP ])
        expect(token).not_to be_valid
        expect(token.errors[:scopes].join).to match(/dev/)
      end

      it "accepts scopes: ['app'] when expose_dev_scope is false" do
        expect(build(:api_token, scopes: [ Scopes::APP ])).to be_valid
      end
    end

    describe "Phase 25 — 01d. strip-on-release auth_scope_only_when_exposed validation" do
      around do |example|
        original = Rails.application.config.x.mcp.expose_auth_scope
        Rails.application.config.x.mcp.expose_auth_scope = false
        example.run
      ensure
        Rails.application.config.x.mcp.expose_auth_scope = original
      end

      it "rejects scopes: ['auth'] when expose_auth_scope is false" do
        token = build(:api_token, scopes: [ Scopes::AUTH ])
        expect(token).not_to be_valid
        expect(token.errors[:scopes].join).to match(/auth/)
      end

      it "rejects scopes: ['auth', 'app'] when expose_auth_scope is false" do
        token = build(:api_token, scopes: [ Scopes::AUTH, Scopes::APP ])
        expect(token).not_to be_valid
        expect(token.errors[:scopes].join).to match(/auth/)
      end

      it "accepts scopes: ['app'] when expose_auth_scope is false" do
        expect(build(:api_token, scopes: [ Scopes::APP ])).to be_valid
      end
    end
  end

  describe "associations" do
    it "belongs to a user" do
      token = create(:api_token)
      expect(token.user).to be_present
    end

    it "does not declare a tenant association" do
      expect(ApiToken.reflect_on_association(:tenant)).to be_nil
    end
  end

  describe ".generate!" do
    let(:user) { create(:user) }

    it "creates a token and returns plaintext exactly once" do
      record, plaintext = ApiToken.generate!(
        user: user,
        name: "test",
        scopes: [ Scopes::DEV ]
      )

      expect(record).to be_persisted
      expect(record.name).to eq("test")
      expect(record.scopes).to eq([ Scopes::DEV ])
      expect(record.user_id).to eq(user.id)
      expect(record.last_token_preview).to eq(plaintext.last(4))
      expect(record.token_digest).to eq(ApiToken.digest(plaintext))
      expect(plaintext).to be_a(String)
      expect(plaintext.length).to be >= 40
    end

    it "accepts an optional expires_at" do
      future = 30.days.from_now
      record, _ = ApiToken.generate!(
        user: user,
        name: "expiring", scopes: [ Scopes::DEV ],
        expires_at: future
      )
      expect(record.expires_at).to be_within(1.second).of(future)
    end

    it "exposes a tenant-free signature" do
      expect(ApiToken.method(:generate!).parameters.map(&:last))
        .to match_array(%i[user name scopes expires_at])
    end
  end

  describe ".authenticate" do
    let(:user) { create(:user) }

    it "returns the token for valid plaintext" do
      _record, plaintext = ApiToken.generate!(
        user: user, name: "auth", scopes: [ Scopes::DEV ]
      )

      result = ApiToken.authenticate(plaintext)
      expect(result).to be_present
      expect(result.name).to eq("auth")
    end

    it "updates last_used_at on success" do
      record, plaintext = ApiToken.generate!(
        user: user, name: "usage", scopes: [ Scopes::DEV ]
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
        user: user, name: "revoked", scopes: [ Scopes::DEV ]
      )
      record.revoke!

      expect(ApiToken.authenticate(plaintext)).to be_nil
    end

    it "returns nil for expired token" do
      record, plaintext = ApiToken.generate!(
        user: user, name: "expired", scopes: [ Scopes::DEV ],
        expires_at: 1.hour.ago
      )
      expect(record.expired?).to be true

      expect(ApiToken.authenticate(plaintext)).to be_nil
    end
  end

  describe "#revoked? / #expired? / #usable?" do
    let(:user) { create(:user) }

    it "is usable when neither revoked nor expired" do
      record, _ = ApiToken.generate!(user: user, name: "ok", scopes: [ Scopes::DEV ])
      expect(record.revoked?).to be false
      expect(record.expired?).to be false
      expect(record.usable?).to be true
    end

    it "is not usable when revoked" do
      record, _ = ApiToken.generate!(user: user, name: "rv", scopes: [ Scopes::DEV ])
      record.revoke!
      expect(record.revoked?).to be true
      expect(record.usable?).to be false
    end

    it "is not usable when expired" do
      record, _ = ApiToken.generate!(
        user: user, name: "ex", scopes: [ Scopes::DEV ],
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

    it "raises Api::AuthConfigurationMissing when the resolved pepper is blank" do
      allow(ApiToken).to receive(:pepper).and_return(nil)
      expect { ApiToken.digest("anything") }.to raise_error(Api::AuthConfigurationMissing)
    end
  end

  describe ".pepper" do
    it "returns the credential when set" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return("from-credential")
      expect(ApiToken.pepper).to eq("from-credential")
    end

    it "falls back to PITO_TOKENS_PEPPER when the credential is absent" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)
      original = ENV["PITO_TOKENS_PEPPER"]
      ENV["PITO_TOKENS_PEPPER"] = "from-env"
      expect(ApiToken.pepper).to eq("from-env")
    ensure
      ENV["PITO_TOKENS_PEPPER"] = original
    end

    it "falls back to a fixed test pepper in Rails.env.test? when neither credential nor env var is set" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)
      original = ENV["PITO_TOKENS_PEPPER"]
      ENV.delete("PITO_TOKENS_PEPPER")
      expect(Rails.env.test?).to be(true)
      expect(ApiToken.pepper).to eq("test-pepper-not-a-secret")
    ensure
      ENV["PITO_TOKENS_PEPPER"] = original
    end

    it "returns nil in non-test environments when neither credential nor env var is set" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)
      original = ENV["PITO_TOKENS_PEPPER"]
      ENV.delete("PITO_TOKENS_PEPPER")
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      expect(ApiToken.pepper).to be_nil
    ensure
      ENV["PITO_TOKENS_PEPPER"] = original
    end
  end
end
