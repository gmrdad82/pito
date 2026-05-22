# D10 (2026-05-22) — Pito::Theme::Sections service spec.
require "rails_helper"

RSpec.describe Pito::Theme::Sections do
  describe "ACCENTS canonical hex map" do
    it "defines exactly 3 screen accents" do
      expect(described_class::ACCENTS.keys).to contain_exactly(:home, :videos, :games)
    end

    it "home is Dracula Purple" do
      expect(described_class::ACCENTS[:home]).to eq("#bd93f9")
    end

    it "videos is Dracula Red" do
      expect(described_class::ACCENTS[:videos]).to eq("#ff5555")
    end

    it "games is Pale Cobalt" do
      expect(described_class::ACCENTS[:games]).to eq("#7eb6ff")
    end
  end

  describe ".accent" do
    it "returns the hex for each screen" do
      expect(described_class.accent(:home)).to eq("#bd93f9")
      expect(described_class.accent(:videos)).to eq("#ff5555")
      expect(described_class.accent(:games)).to eq("#7eb6ff")
    end

    it "accepts a String key too" do
      expect(described_class.accent("home")).to eq("#bd93f9")
    end

    it "falls back to Dracula Purple for unknown sections" do
      expect(described_class.accent(:unknown)).to eq("#bd93f9")
    end
  end

  describe ".bg" do
    it "returns the section background hex string" do
      expect(described_class.bg(:home)).to eq("#2c2a36")
    end

    it "returns the settings bg #34333b" do
      expect(described_class.bg("settings")).to eq("#34333b")
    end

    it "falls back to DRACULA_BG for unknown sections" do
      expect(described_class.bg(:unknown)).to eq(described_class::DRACULA_BG)
    end
  end

  describe ".border" do
    it "returns a color-mix string with 35% accent over Dracula bg" do
      expect(described_class.border(:videos)).to include("color-mix")
      expect(described_class.border(:videos)).to include("#ff5555")
      expect(described_class.border(:videos)).to include("35%")
    end
  end

  describe ".focus_tint" do
    it "returns a color-mix string with 18% accent over transparent" do
      expect(described_class.focus_tint(:games)).to include("color-mix")
      expect(described_class.focus_tint(:games)).to include("#7eb6ff")
      expect(described_class.focus_tint(:games)).to include("18%")
      expect(described_class.focus_tint(:games)).to include("transparent")
    end
  end

  describe "ACCENT full table" do
    it "defines settings as Dracula Orange" do
      expect(described_class::ACCENT["settings"]).to eq("#ffb86c")
    end

    it "defines channels as Dracula Red" do
      expect(described_class::ACCENT["channels"]).to eq("#ff5555")
    end
  end

  describe "BG table" do
    it "defines settings bg as #34333b (user-locked)" do
      expect(described_class::BG["settings"]).to eq("#34333b")
    end

    it "defines home bg" do
      expect(described_class::BG["home"]).to eq("#2c2a36")
    end
  end

  describe ".mix pure-Ruby color-mix" do
    it "returns a #rrggbb string" do
      result = described_class.mix("#ffffff", 100, "#000000")
      expect(result).to match(/\A#[0-9a-f]{6}\z/)
    end

    it "100% accent returns the accent color" do
      expect(described_class.mix("#bd93f9", 100, "#282a36")).to eq("#bd93f9")
    end

    it "0% accent returns the background color" do
      expect(described_class.mix("#bd93f9", 0, "#282a36")).to eq("#282a36")
    end

    it "raises ArgumentError for out-of-range percent" do
      expect { described_class.mix("#ffffff", 101, "#000000") }.to raise_error(ArgumentError)
      expect { described_class.mix("#ffffff", -1, "#000000") }.to raise_error(ArgumentError)
    end
  end

  describe ".section_border" do
    it "returns a #rrggbb string blending accent into section bg" do
      result = described_class.section_border(:home)
      expect(result).to match(/\A#[0-9a-f]{6}\z/)
    end
  end
end
