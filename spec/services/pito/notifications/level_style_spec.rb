# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Notifications::LevelStyle do
  describe ".style_for" do
    it "maps each known level to an emoji + slack + discord color" do
      expect(described_class.style_for("info")).to    eq(emoji: "ℹ️",  slack: "#5170ff", discord: 0x5170ff)
      expect(described_class.style_for("success")).to eq(emoji: "✅", slack: "good",    discord: 0x1abc9c)
      expect(described_class.style_for("warning")).to eq(emoji: "⚠️", slack: "warning", discord: 0xf1c40f)
      expect(described_class.style_for("error")).to   eq(emoji: "🛑", slack: "danger",  discord: 0xe74c3c)
    end

    it "falls back to the info style for an unknown level" do
      expect(described_class.style_for("bogus")).to eq(described_class::STYLES.fetch("info"))
      expect(described_class.style_for(nil)).to eq(described_class::STYLES.fetch("info"))
    end
  end

  describe "accessors" do
    it "exposes emoji / slack_color / discord_color" do
      expect(described_class.emoji("error")).to eq("🛑")
      expect(described_class.slack_color("error")).to eq("danger")
      expect(described_class.discord_color("error")).to eq(0xe74c3c)
    end
  end
end
