# frozen_string_literal: true

require "rails_helper"

# AppSetting sync helpers — 2026-05-25 (sync-rebuild). The
# `pito.sync.*` localStorage layer has been killed; server-side
# AppSetting rows are the canonical state for every per-target sync
# flag.
RSpec.describe AppSetting do
  describe ".sync_enabled?" do
    it "defaults to true when no row exists for the target" do
      expect(described_class.sync_enabled?("home.stack")).to be(true)
    end

    it "returns false when the row is set to 'no'" do
      described_class.set_sync("home.stack", false)
      expect(described_class.sync_enabled?("home.stack")).to be(false)
    end

    it "returns true when the row is set to 'yes'" do
      described_class.set_sync("home.stack", true)
      expect(described_class.sync_enabled?("home.stack")).to be(true)
    end

    it "treats unrecognized values as enabled (defensive default)" do
      described_class.set("sync.home.stack", "maybe")
      expect(described_class.sync_enabled?("home.stack")).to be(true)
    end
  end

  describe ".set_sync" do
    it "writes 'yes' for true" do
      described_class.set_sync("home.security", true)
      expect(described_class.get("sync.home.security")).to eq("yes")
    end

    it "writes 'no' for false" do
      described_class.set_sync("home.security", false)
      expect(described_class.get("sync.home.security")).to eq("no")
    end

    it "is idempotent across calls (no duplicate rows)" do
      described_class.set_sync("home.calendar", false)
      described_class.set_sync("home.calendar", false)
      described_class.set_sync("home.calendar", true)
      expect(described_class.where(key: "sync.home.calendar").count).to eq(1)
    end

    it "uses the canonical sync. key prefix" do
      described_class.set_sync("app", true)
      expect(described_class.where(key: "sync.app")).to exist
    end
  end

  describe "key prefix constant" do
    it "freezes the SYNC_KEY_PREFIX" do
      expect(described_class::SYNC_KEY_PREFIX).to eq("sync.")
      expect(described_class::SYNC_KEY_PREFIX).to be_frozen
    end
  end
end
