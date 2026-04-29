require "rails_helper"

RSpec.describe McpAccessToken, type: :model do
  describe "validations" do
    it { is_expected.to validate_presence_of(:name) }
    it { is_expected.to validate_presence_of(:token_digest) }
    it { is_expected.to validate_presence_of(:last_token_preview) }

    it "enforces unique token_digest" do
      digest = McpAccessToken.digest("test-token")
      create(:mcp_access_token, token_digest: digest)
      duplicate = build(:mcp_access_token, token_digest: digest)
      expect(duplicate).not_to be_valid
    end
  end

  describe ".generate!" do
    it "creates a token and returns plaintext" do
      token, plaintext = McpAccessToken.generate!(name: "test")

      expect(token).to be_persisted
      expect(token.name).to eq("test")
      expect(token.last_token_preview).to eq(plaintext.last(4))
      expect(token.token_digest).to eq(McpAccessToken.digest(plaintext))
    end
  end

  describe ".authenticate" do
    it "returns token for valid plaintext" do
      _token, plaintext = McpAccessToken.generate!(name: "auth-test")

      result = McpAccessToken.authenticate(plaintext)
      expect(result).to be_present
      expect(result.name).to eq("auth-test")
    end

    it "updates last_used_at" do
      _token, plaintext = McpAccessToken.generate!(name: "usage-test")

      expect { McpAccessToken.authenticate(plaintext) }
        .to change { McpAccessToken.last.last_used_at }.from(nil)
    end

    it "returns nil for invalid plaintext" do
      expect(McpAccessToken.authenticate("bogus")).to be_nil
    end

    it "returns nil for blank plaintext" do
      expect(McpAccessToken.authenticate("")).to be_nil
      expect(McpAccessToken.authenticate(nil)).to be_nil
    end

    it "returns nil for revoked token" do
      token, plaintext = McpAccessToken.generate!(name: "revoked-test")
      token.revoke!

      expect(McpAccessToken.authenticate(plaintext)).to be_nil
    end
  end

  describe "#revoke!" do
    it "sets revoked_at" do
      token, _plaintext = McpAccessToken.generate!(name: "revoke-test")
      expect(token.revoked?).to be false

      token.revoke!
      expect(token.revoked?).to be true
      expect(token.revoked_at).to be_present
    end
  end

  describe ".digest" do
    it "produces consistent digests" do
      expect(McpAccessToken.digest("hello")).to eq(McpAccessToken.digest("hello"))
    end

    it "produces different digests for different inputs" do
      expect(McpAccessToken.digest("hello")).not_to eq(McpAccessToken.digest("world"))
    end
  end
end
