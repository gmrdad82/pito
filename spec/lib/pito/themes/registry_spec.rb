require "rails_helper"

RSpec.describe Pito::Themes::Registry do
  describe ".all" do
    it "returns an Array" do
      expect(described_class.all).to be_an(Array)
    end

    it "contains at least two themes" do
      expect(described_class.all.size).to be >= 2
    end

    it "all entries are Definition objects" do
      described_class.all.each do |d|
        expect(d).to be_a(Pito::Themes::Definition)
      end
    end
  end

  describe ".names" do
    it "includes 'tokyo-night'" do
      expect(described_class.names).to include("tokyo-night")
    end

    it "includes 'dracula'" do
      expect(described_class.names).to include("dracula")
    end
  end

  describe ".find" do
    it "returns the Definition for a known slug" do
      result = described_class.find("tokyo-night")
      expect(result).to be_a(Pito::Themes::Definition)
      expect(result.slug).to eq("tokyo-night")
    end

    it "returns nil for an unknown slug" do
      expect(described_class.find("no-such-theme")).to be_nil
    end
  end

  describe ".grouped" do
    it "returns a Hash keyed by mode symbol" do
      expect(described_class.grouped).to be_a(Hash)
    end

    it "places tokyo-night in :dark" do
      dark = described_class.grouped[:dark] || []
      slugs = dark.map(&:slug)
      expect(slugs).to include("tokyo-night")
    end

    it "places dracula in :dark" do
      dark = described_class.grouped[:dark] || []
      slugs = dark.map(&:slug)
      expect(slugs).to include("dracula")
    end
  end

  describe ".default" do
    it "returns the tokyo-night Definition" do
      expect(described_class.default.slug).to eq("tokyo-night")
    end
  end

  # Regression guard: tokyo-night tokens must exactly match the migrated values.
  describe "tokyo-night token regression" do
    subject(:tn) { described_class.find("tokyo-night") }

    it "bg_root is #1a1b26" do
      expect(tn.tokens[:bg_root]).to eq("#1a1b26")
    end

    it "fg_default is #c0caf5" do
      expect(tn.tokens[:fg_default]).to eq("#c0caf5")
    end

    it "bg_surface is #1f2335 (override)" do
      expect(tn.tokens[:bg_surface]).to eq("#1f2335")
    end

    it "bg_elevated is #24283b (override)" do
      expect(tn.tokens[:bg_elevated]).to eq("#24283b")
    end

    it "border_default is #292e42 (override)" do
      expect(tn.tokens[:border_default]).to eq("#292e42")
    end

    it "border_faded is #414868 (override)" do
      expect(tn.tokens[:border_faded]).to eq("#414868")
    end

    it "fg_dim is #565f89 (override)" do
      expect(tn.tokens[:fg_dim]).to eq("#565f89")
    end

    it "fg_faded is #414868 (override)" do
      expect(tn.tokens[:fg_faded]).to eq("#414868")
    end

    it "accent_purple is #bb9af7" do
      expect(tn.tokens[:accent_purple]).to eq("#bb9af7")
    end

    it "accent_blue is #7aa2f7" do
      expect(tn.tokens[:accent_blue]).to eq("#7aa2f7")
    end

    it "accent_cyan is #7dcfff" do
      expect(tn.tokens[:accent_cyan]).to eq("#7dcfff")
    end

    it "accent_green is #9ece6a" do
      expect(tn.tokens[:accent_green]).to eq("#9ece6a")
    end

    it "accent_yellow is #e0af68" do
      expect(tn.tokens[:accent_yellow]).to eq("#e0af68")
    end

    it "accent_orange is #ff9e64" do
      expect(tn.tokens[:accent_orange]).to eq("#ff9e64")
    end

    it "accent_red is #f7768e" do
      expect(tn.tokens[:accent_red]).to eq("#f7768e")
    end

    it "brand_pito is #5170ff" do
      expect(tn.tokens[:brand_pito]).to eq("#5170ff")
    end

    it "mode is :dark" do
      expect(tn.mode).to eq(:dark)
    end

    it "label is 'Tokyo Night'" do
      expect(tn.label).to eq("Tokyo Night")
    end
  end
end
