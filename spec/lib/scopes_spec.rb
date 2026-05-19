require "rails_helper"

# Phase 10 — MCP scope simplification (ADR 0004) + Phase 29 (MCP cut,
# 2026-05-19). With both the dev knowledge base tools and the auth
# administration tools removed, the catalog collapses to a single
# scope, `app`.
RSpec.describe Scopes do
  describe "constants" do
    it "exposes Scopes::APP as 'app'" do
      expect(described_class::APP).to eq("app")
    end

    it "no longer defines the retired DEV constant" do
      expect(described_class.const_defined?(:DEV)).to be(false)
    end

    it "no longer defines the retired AUTH constant" do
      expect(described_class.const_defined?(:AUTH)).to be(false)
    end

    it "has no read/write split constants (full rewrite from the 9-scope catalog)" do
      %i[DEV_READ DEV_WRITE YT_READ YT_WRITE YT_DESTRUCTIVE
         WEBSITE_READ WEBSITE_WRITE PROJECT_READ PROJECT_WRITE].each do |sym|
        expect(described_class.const_defined?(sym)).to be(false), "expected Scopes to NOT define #{sym}"
      end
    end
  end

  describe ".all" do
    it "returns ['app']" do
      expect(described_class.all).to eq([ "app" ])
    end

    it "returns a frozen array" do
      expect(described_class.all).to be_frozen
    end
  end

  describe "ALL" do
    it "equals ['app']" do
      expect(described_class::ALL).to eq([ "app" ])
    end

    it "is frozen so callers can't mutate the catalog" do
      expect(described_class::ALL).to be_frozen
    end
  end

  describe "DESCRIPTIONS" do
    it "is frozen" do
      expect(described_class::DESCRIPTIONS).to be_frozen
    end

    it "has one entry" do
      expect(described_class::DESCRIPTIONS.size).to eq(1)
    end

    it "has a non-empty description for APP" do
      expect(described_class::DESCRIPTIONS[described_class::APP]).to be_a(String)
      expect(described_class::DESCRIPTIONS[described_class::APP]).not_to be_empty
    end

    it "uses the locked app copy" do
      expect(described_class::DESCRIPTIONS[described_class::APP])
        .to eq("application access. manage channels, videos, projects, and the calendar.")
    end
  end
end
