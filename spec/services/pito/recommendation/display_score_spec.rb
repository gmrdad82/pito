# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::DisplayScore do
  describe ".display_score" do
    it "maps a similarity exactly at the floor to 0" do
      expect(described_class.display_score(0.5, floor: 0.5)).to eq(0.0)
    end

    it "maps similarity 1.0 (identical) to 100, regardless of floor" do
      expect(described_class.display_score(1.0, floor: 0.5)).to eq(100.0)
      expect(described_class.display_score(1.0, floor: 0.85)).to eq(100.0)
    end

    it "scales linearly between floor and 1.0 (midpoint of the range → 50)" do
      expect(described_class.display_score(0.75, floor: 0.5)).to eq(50.0)
    end

    it "clamps a below-floor similarity to 0, never negative" do
      expect(described_class.display_score(0.2, floor: 0.5)).to eq(0.0)
    end

    it "clamps an above-1.0 similarity to 100 (defensive; real cosine similarity never exceeds 1.0)" do
      expect(described_class.display_score(1.2, floor: 0.5)).to eq(100.0)
    end

    it "casts a non-Float similarity before scaling" do
      expect(described_class.display_score(1, floor: 0.5)).to eq(100.0)
    end

    it "anchors 100 at a caller-measured ceiling instead of 1.0 when given one (3.1.2 — query→doc regimes never reach 1.0)" do
      expect(described_class.display_score(0.70, floor: 0.55, ceiling: 0.70)).to eq(100.0)
      expect(described_class.display_score(0.625, floor: 0.55, ceiling: 0.70)).to eq(50.0)
    end

    it "clamps an above-ceiling similarity to 100" do
      expect(described_class.display_score(0.9, floor: 0.55, ceiling: 0.70)).to eq(100.0)
    end
  end

  describe "VID_FLOOR" do
    it "is the measured 2026-07-16 prod vid random-pair floor" do
      expect(described_class::VID_FLOOR).to eq(0.85)
    end
  end

  describe "CONVERSATION_FLOOR" do
    it "is the measured 2026-07-16 prod conversation random-pair floor" do
      expect(described_class::CONVERSATION_FLOOR).to eq(0.50)
    end
  end
end
