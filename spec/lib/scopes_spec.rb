require "rails_helper"

RSpec.describe Scopes do
  describe "ALL" do
    it "contains exactly the nine catalog entries" do
      expect(described_class::ALL.size).to eq(9)
    end

    it "is frozen so callers can't mutate the catalog" do
      expect(described_class::ALL).to be_frozen
    end

    it "contains the dev:* scopes" do
      expect(described_class::ALL).to include("dev:read", "dev:write")
    end

    it "contains the yt:* scopes (read, write, destructive)" do
      expect(described_class::ALL).to include("yt:read", "yt:write", "yt:destructive")
    end

    it "contains the website:* scopes" do
      expect(described_class::ALL).to include("website:read", "website:write")
    end

    it "contains the project:* scopes" do
      expect(described_class::ALL).to include("project:read", "project:write")
    end
  end

  describe "DESCRIPTIONS" do
    it "is frozen" do
      expect(described_class::DESCRIPTIONS).to be_frozen
    end

    it "has a description entry for every catalog scope" do
      expect(described_class::DESCRIPTIONS.keys).to match_array(described_class::ALL)
    end

    it "has non-empty descriptions" do
      described_class::DESCRIPTIONS.each_value do |desc|
        expect(desc).to be_a(String)
        expect(desc).not_to be_empty
      end
    end
  end

  describe "constants" do
    it "exposes named constants for each catalog entry" do
      expect(described_class::DEV_READ).to       eq("dev:read")
      expect(described_class::DEV_WRITE).to      eq("dev:write")
      expect(described_class::YT_READ).to        eq("yt:read")
      expect(described_class::YT_WRITE).to       eq("yt:write")
      expect(described_class::YT_DESTRUCTIVE).to eq("yt:destructive")
      expect(described_class::WEBSITE_READ).to   eq("website:read")
      expect(described_class::WEBSITE_WRITE).to  eq("website:write")
      expect(described_class::PROJECT_READ).to   eq("project:read")
      expect(described_class::PROJECT_WRITE).to  eq("project:write")
    end
  end
end
