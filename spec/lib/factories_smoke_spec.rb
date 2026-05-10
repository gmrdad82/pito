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
      # gone with the columns they targeted. The `:connected` trait
      # was retired alongside the derived connected display surface;
      # tests pass an explicit `youtube_connection:` association
      # when they need an OAuth-linked channel.
      expect(FactoryBot.build(:channel, :starred)).to be_valid
    end
  end
end
