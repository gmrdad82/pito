require "rails_helper"

# Phase 14 §1 — top-level `Igdb` module. Exposes `credentials` and
# `credentials!`, the latter raising `Igdb::Client::MissingCredentials`
# when the credentials block is absent or one of the two required keys
# (`client_id`, `client_secret`) is blank. The lazy reader keeps boots
# clean in development / test where the credential block may not exist.
RSpec.describe Igdb do
  describe ".credentials" do
    it "delegates to Rails.application.credentials.igdb" do
      stub = { client_id: "cid", client_secret: "secret" }
      allow(Rails.application.credentials).to receive(:igdb).and_return(stub)
      expect(described_class.credentials).to eq(stub)
    end

    it "returns nil when the credentials block is absent" do
      allow(Rails.application.credentials).to receive(:igdb).and_return(nil)
      expect(described_class.credentials).to be_nil
    end
  end

  describe ".credentials!" do
    it "returns the credentials hash when both keys are present" do
      stub = { client_id: "cid", client_secret: "secret" }
      allow(Rails.application.credentials).to receive(:igdb).and_return(stub)
      expect(described_class.credentials!).to eq(stub)
    end

    it "raises MissingCredentials when the block is nil" do
      allow(Rails.application.credentials).to receive(:igdb).and_return(nil)
      expect { described_class.credentials! }
        .to raise_error(Igdb::Client::MissingCredentials, /missing client_id\/client_secret/)
    end

    it "raises MissingCredentials when the block is an empty hash" do
      allow(Rails.application.credentials).to receive(:igdb).and_return({})
      expect { described_class.credentials! }
        .to raise_error(Igdb::Client::MissingCredentials)
    end

    it "raises MissingCredentials when client_id is blank" do
      stub = { client_id: "", client_secret: "secret" }
      allow(Rails.application.credentials).to receive(:igdb).and_return(stub)
      expect { described_class.credentials! }
        .to raise_error(Igdb::Client::MissingCredentials)
    end

    it "raises MissingCredentials when client_secret is blank" do
      stub = { client_id: "cid", client_secret: nil }
      allow(Rails.application.credentials).to receive(:igdb).and_return(stub)
      expect { described_class.credentials! }
        .to raise_error(Igdb::Client::MissingCredentials)
    end

    it "raises MissingCredentials when both keys are blank" do
      stub = { client_id: nil, client_secret: nil }
      allow(Rails.application.credentials).to receive(:igdb).and_return(stub)
      expect { described_class.credentials! }
        .to raise_error(Igdb::Client::MissingCredentials)
    end

    it "is a module-function (callable on the module without an instance)" do
      expect(described_class).to respond_to(:credentials!)
      expect(described_class).to respond_to(:credentials)
    end
  end
end
