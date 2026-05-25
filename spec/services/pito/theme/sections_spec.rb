# D10 (2026-05-22) — Pito::Theme::Sections service spec.
# 2026-05-26 — Updated for Tokyo Night migration.
require "rails_helper"

RSpec.describe Pito::Theme::Sections do
  describe "ACCENTS canonical hex map" do
    it "defines exactly 3 screen accents" do
      expect(described_class::ACCENTS.keys).to contain_exactly(:home, :videos, :games)
    end

    it "home is Tokyo Night Blue" do
      expect(described_class::ACCENTS[:home]).to eq("#7aa2f7")
    end

    it "videos is Tokyo Night Red" do
      expect(described_class::ACCENTS[:videos]).to eq("#f7768e")
    end

    it "games is Tokyo Night Teal" do
      expect(described_class::ACCENTS[:games]).to eq("#1abc9c")
    end
  end

  describe ".accent" do
    it "returns the hex for each screen" do
      expect(described_class.accent(:home)).to eq("#7aa2f7")
      expect(described_class.accent(:videos)).to eq("#f7768e")
      expect(described_class.accent(:games)).to eq("#1abc9c")
    end

    it "accepts a String key too" do
      expect(described_class.accent("home")).to eq("#7aa2f7")
    end

    it "falls back to Tokyo Night Blue for unknown sections" do
      expect(described_class.accent(:unknown)).to eq("#7aa2f7")
    end
  end

  describe ".bg" do
    # 2026-05-22 — bg now derives from the canonical 4%-accent-over-
    # Tokyo-Night-bg recipe (matching `tmp/dracula-swatches-v2.html` §
    # Section pane composition). The only override is `settings`,
    # which the user locked to #34333b on 2026-05-20.

    it "returns the 4% recipe bg for home (Tokyo Night Blue over Tokyo Night bg)" do
      expect(described_class.bg(:home)).to eq("#1e202e")
    end

    it "returns the 4% recipe bg for channels (Tokyo Night Blue)" do
      expect(described_class.bg(:channels)).to eq("#1e202e")
    end

    it "returns the 4% recipe bg for videos (Tokyo Night Red)" do
      expect(described_class.bg(:videos)).to eq("#231f2a")
    end

    it "returns the 4% recipe bg for games + projects (Tokyo Night Teal)" do
      expect(described_class.bg(:games)).to eq("#1a212b")
      expect(described_class.bg(:projects)).to eq("#1e202e")
    end

    it "returns the 4% recipe bg for notifications + calendar (Tokyo Night Blue)" do
      expect(described_class.bg(:notifications)).to eq("#1e202e")
      expect(described_class.bg(:calendar)).to eq("#1e202e")
    end

    it "returns the user-locked bg for settings (#34333b — overrides recipe)" do
      expect(described_class.bg("settings")).to eq("#34333b")
    end

    it "falls back to TOKYO_NIGHT_BG for unknown sections" do
      expect(described_class.bg(:unknown)).to eq(described_class::TOKYO_NIGHT_BG)
    end
  end

  describe ".border" do
    it "returns a color-mix string with 35% accent over Tokyo Night bg" do
      expect(described_class.border(:videos)).to include("color-mix")
      expect(described_class.border(:videos)).to include("#f7768e")
      expect(described_class.border(:videos)).to include("35%")
    end
  end

  describe ".focus_tint" do
    it "returns a color-mix string with 18% accent over transparent" do
      expect(described_class.focus_tint(:games)).to include("color-mix")
      expect(described_class.focus_tint(:games)).to include("#1abc9c")
      expect(described_class.focus_tint(:games)).to include("18%")
      expect(described_class.focus_tint(:games)).to include("transparent")
    end
  end

  describe "ACCENT full table" do
    it "defines settings as Tokyo Night Blue" do
      expect(described_class::ACCENT["settings"]).to eq("#7aa2f7")
    end

    it "defines channels as Tokyo Night Blue" do
      expect(described_class::ACCENT["channels"]).to eq("#7aa2f7")
    end
  end

  describe "BG table" do
    it "defines settings bg as #34333b (user-locked, overrides recipe)" do
      expect(described_class::BG["settings"]).to eq("#34333b")
    end

    it "defines home bg as the canonical 4% recipe (#1e202e)" do
      expect(described_class::BG["home"]).to eq("#1e202e")
    end

    it "derives every non-settings section bg from the 4% recipe" do
      %w[home channels videos games projects notifications calendar].each do |section|
        expected = described_class.mix(described_class.accent(section), 4, "#1a1b26")
        expect(described_class::BG[section]).to eq(expected),
          "expected #{section} BG to match 4%% recipe (#{expected}), got #{described_class::BG[section]}"
      end
    end
  end

  describe ".mix pure-Ruby color-mix" do
    it "returns a #rrggbb string" do
      result = described_class.mix("#ffffff", 100, "#000000")
      expect(result).to match(/\A#[0-9a-f]{6}\z/)
    end

    it "100% accent returns the accent color" do
      expect(described_class.mix("#7aa2f7", 100, "#1a1b26")).to eq("#7aa2f7")
    end

    it "0% accent returns the background color" do
      expect(described_class.mix("#7aa2f7", 0, "#1a1b26")).to eq("#1a1b26")
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
