require "rails_helper"

# Smoke test that the Phase A factories build valid records.
RSpec.describe "FactoryBot Phase A factories" do
  describe ":user" do
    it "builds a valid record" do
      expect(FactoryBot.build(:user)).to be_valid
    end
  end

  describe ":channel" do
    it "builds a valid record" do
      expect(FactoryBot.build(:channel)).to be_valid
    end

    it "builds valid records for each trait" do
      # Phase 7 Path A2 — `:syncing` and `:fully_loaded` traits are
      # gone with the columns they targeted.
      expect(FactoryBot.build(:channel, :starred)).to be_valid
      expect(FactoryBot.build(:channel, :connected)).to be_valid
    end
  end
end
