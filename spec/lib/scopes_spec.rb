require "rails_helper"

# Phase 10 — MCP scope simplification (ADR 0004) + Phase 25 — 01d.
# The catalog is `dev` + `app` + `auth`; both `dev` and `auth` strip
# on release via dedicated config flags.
RSpec.describe Scopes do
  describe "constants" do
    it "exposes Scopes::DEV as 'dev'" do
      expect(described_class::DEV).to eq("dev")
    end

    it "exposes Scopes::APP as 'app'" do
      expect(described_class::APP).to eq("app")
    end

    it "exposes Scopes::AUTH as 'auth'" do
      expect(described_class::AUTH).to eq("auth")
    end

    it "has no read/write split constants (full rewrite from the 9-scope catalog)" do
      %i[DEV_READ DEV_WRITE YT_READ YT_WRITE YT_DESTRUCTIVE
         WEBSITE_READ WEBSITE_WRITE PROJECT_READ PROJECT_WRITE].each do |sym|
        expect(described_class.const_defined?(sym)).to be(false), "expected Scopes to NOT define #{sym}"
      end
    end
  end

  describe ".all" do
    it "in the test environment, returns ['dev', 'app', 'auth'] in array order" do
      expect(described_class.all).to eq([ "dev", "app", "auth" ])
    end

    it "returns ['app', 'auth'] when expose_dev_scope is false" do
      allow(described_class).to receive(:dev_exposed?).and_return(false)
      expect(described_class.all).to eq([ "app", "auth" ])
    end

    it "returns ['dev', 'app'] when expose_auth_scope is false" do
      allow(described_class).to receive(:auth_exposed?).and_return(false)
      expect(described_class.all).to eq([ "dev", "app" ])
    end

    it "returns ['app'] when both dev and auth are stripped" do
      allow(described_class).to receive(:dev_exposed?).and_return(false)
      allow(described_class).to receive(:auth_exposed?).and_return(false)
      expect(described_class.all).to eq([ "app" ])
    end

    it "returns a frozen array" do
      expect(described_class.all).to be_frozen
    end
  end

  describe "ALL" do
    it "in the test environment, equals ['dev', 'app', 'auth']" do
      expect(described_class::ALL).to eq([ "dev", "app", "auth" ])
    end

    it "is frozen so callers can't mutate the catalog" do
      expect(described_class::ALL).to be_frozen
    end
  end

  describe ".dev_exposed?" do
    it "returns true in the test environment by default" do
      expect(described_class.dev_exposed?).to be(true)
    end

    it "reflects the live config flag" do
      original = Rails.application.config.x.mcp.expose_dev_scope
      Rails.application.config.x.mcp.expose_dev_scope = false
      expect(described_class.dev_exposed?).to be(false)
    ensure
      Rails.application.config.x.mcp.expose_dev_scope = original
    end
  end

  describe ".auth_exposed?" do
    it "returns true in the test environment by default" do
      expect(described_class.auth_exposed?).to be(true)
    end

    it "reflects the live config flag" do
      original = Rails.application.config.x.mcp.expose_auth_scope
      Rails.application.config.x.mcp.expose_auth_scope = false
      expect(described_class.auth_exposed?).to be(false)
    ensure
      Rails.application.config.x.mcp.expose_auth_scope = original
    end
  end

  describe "DESCRIPTIONS" do
    it "is frozen" do
      expect(described_class::DESCRIPTIONS).to be_frozen
    end

    it "has three entries" do
      expect(described_class::DESCRIPTIONS.size).to eq(3)
    end

    it "has a non-empty description for DEV" do
      expect(described_class::DESCRIPTIONS[described_class::DEV]).to be_a(String)
      expect(described_class::DESCRIPTIONS[described_class::DEV]).not_to be_empty
    end

    it "has a non-empty description for APP" do
      expect(described_class::DESCRIPTIONS[described_class::APP]).to be_a(String)
      expect(described_class::DESCRIPTIONS[described_class::APP]).not_to be_empty
    end

    it "has a non-empty description for AUTH" do
      expect(described_class::DESCRIPTIONS[described_class::AUTH]).to be_a(String)
      expect(described_class::DESCRIPTIONS[described_class::AUTH]).not_to be_empty
    end

    it "uses the locked dev copy" do
      expect(described_class::DESCRIPTIONS[described_class::DEV])
        .to eq("read and capture developer docs.")
    end

    it "uses the locked app copy" do
      expect(described_class::DESCRIPTIONS[described_class::APP])
        .to eq("application access. manage channels, videos, projects, and the calendar.")
    end
  end
end
