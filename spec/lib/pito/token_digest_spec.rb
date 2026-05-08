require "rails_helper"

RSpec.describe Pito::TokenDigest do
  describe ".pepper" do
    it "returns the credential when set" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return("from-credential")
      expect(described_class.pepper).to eq("from-credential")
    end

    it "falls back to ENV in non-test runs" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)
      stub_const("ENV", ENV.to_h.merge("PITO_TOKENS_PEPPER" => "from-env"))
      # The test-only fallback takes precedence over ENV in test runs, so
      # stubbing the credential and `Rails.env.test?` together is enough
      # to drive ENV.
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("development"))
      expect(described_class.pepper).to eq("from-env")
    end

    it "returns the well-known test fallback in Rails.env.test?" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)
      stub_const("ENV", ENV.to_h.merge("PITO_TOKENS_PEPPER" => nil))
      expect(described_class.pepper).to eq("test-pepper-not-a-secret")
    end

    it "returns nil in production with no credential and no ENV" do
      allow(Rails.application.credentials).to receive(:dig).with(:tokens, :pepper).and_return(nil)
      stub_const("ENV", ENV.to_h.merge("PITO_TOKENS_PEPPER" => nil))
      allow(Rails).to receive(:env).and_return(ActiveSupport::StringInquirer.new("production"))
      expect(described_class.pepper).to be_nil
    end
  end

  describe ".call" do
    it "computes a deterministic HMAC-SHA256 hex digest" do
      first  = described_class.call("hello")
      second = described_class.call("hello")
      expect(first).to eq(second)
      expect(first).to match(/\A[0-9a-f]{64}\z/)
    end

    it "differs across plaintexts" do
      expect(described_class.call("a")).not_to eq(described_class.call("b"))
    end

    it "raises Api::AuthConfigurationMissing when no pepper resolves" do
      allow(described_class).to receive(:pepper).and_return(nil)
      expect { described_class.call("anything") }.to raise_error(Api::AuthConfigurationMissing)
    end

    it "produces the same digest as ApiToken.digest for the same plaintext" do
      plaintext = "shared-plaintext"
      # Both call paths route through Pito::TokenDigest now. ApiToken's
      # public `digest` API stays — verify the two callers see identical
      # output so a Session and an ApiToken minted from the same plaintext
      # would land on the same row.
      expect(ApiToken.digest(plaintext)).to eq(described_class.call(plaintext))
    end

    it "honors an explicit pepper override" do
      a = described_class.call("plain", pepper: "pepper-a")
      b = described_class.call("plain", pepper: "pepper-b")
      expect(a).not_to eq(b)
    end
  end
end
