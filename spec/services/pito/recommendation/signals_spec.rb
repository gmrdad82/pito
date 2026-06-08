# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::Signals do
  describe ".embedding" do
    it "maps distance 0 (identical) to 100" do
      expect(described_class.embedding(0.0)).to eq(100.0)
    end

    it "maps distance 1 (orthogonal) to 0" do
      expect(described_class.embedding(1.0)).to eq(0.0)
    end

    it "maps a mid distance linearly (0.25 → 75)" do
      expect(described_class.embedding(0.25)).to eq(75.0)
    end

    it "clamps an opposite-vector distance (2.0) to 0, never negative" do
      expect(described_class.embedding(2.0)).to eq(0.0)
    end

    it "returns 0 for a nil distance (no embedding)" do
      expect(described_class.embedding(nil)).to eq(0.0)
    end
  end

  describe ".jaccard" do
    it "is 100 for identical sets" do
      expect(described_class.jaccard([ 1, 2, 3 ], [ 3, 2, 1 ])).to eq(100.0)
    end

    it "is 0 for disjoint sets" do
      expect(described_class.jaccard([ 1, 2 ], [ 3, 4 ])).to eq(0.0)
    end

    it "computes partial overlap (|∩|/|∪|): one shared of three union → 33.3" do
      expect(described_class.jaccard([ 1, 2 ], [ 2, 3 ])).to be_within(0.01).of(33.33)
    end

    it "is 0 when both sets are empty (absence is not a match)" do
      expect(described_class.jaccard([], [])).to eq(0.0)
    end

    it "is 0 when one set is empty" do
      expect(described_class.jaccard([ 1 ], [])).to eq(0.0)
    end

    it "ignores duplicates / order" do
      expect(described_class.jaccard([ 1, 1, 2 ], [ 2, 2, 1 ])).to eq(100.0)
    end
  end

  describe ".score_proximity" do
    it "is 100 for equal scores" do
      expect(described_class.score_proximity(80, 80)).to eq(100.0)
    end

    it "is 0 for scores 100 apart" do
      expect(described_class.score_proximity(0, 100)).to eq(0.0)
    end

    it "is 90 for a 10-point gap" do
      expect(described_class.score_proximity(88, 78)).to eq(90.0)
    end

    it "is symmetric" do
      expect(described_class.score_proximity(40, 70)).to eq(described_class.score_proximity(70, 40))
    end

    it "returns 0 when either score is nil" do
      expect(described_class.score_proximity(nil, 50)).to eq(0.0)
      expect(described_class.score_proximity(50, nil)).to eq(0.0)
    end
  end

  # ── v2 facet signals ────────────────────────────────────────────────────────

  describe ".score_smile" do
    it "scores the mid-band smudge at the floor (SMILE_BASE) even when equal" do
      expect(described_class.score_smile(75, 75)).to eq(40.0)
    end

    it "amplifies two elite (>90) scores far above the mid band" do
      expect(described_class.score_smile(95, 95)).to eq(70.0)
      expect(described_class.score_smile(100, 100)).to eq(100.0)
      expect(described_class.score_smile(95, 95)).to be > described_class.score_smile(75, 75)
    end

    it "amplifies two bad (<60) scores too — bad relates to bad" do
      expect(described_class.score_smile(52, 52)).to be > described_class.score_smile(75, 75)
    end

    it "does NOT amplify across opposite tails (one elite, one bad)" do
      expect(described_class.score_smile(95, 52)).to be < described_class.score_smile(95, 95)
    end

    it "returns 0 when either score is nil" do
      expect(described_class.score_smile(nil, 95)).to eq(0.0)
    end
  end

  describe ".ttb_smile" do
    def hours(h) = (h * 3600)

    it "scores generic (~35h) games at the floor when equal" do
      expect(described_class.ttb_smile(hours(35), hours(35))).to eq(40.0)
    end

    it "amplifies two long (≥150h) epics above generic" do
      expect(described_class.ttb_smile(hours(200), hours(200))).to eq(100.0)
      expect(described_class.ttb_smile(hours(200), hours(200))).to be > described_class.ttb_smile(hours(35), hours(35))
    end

    it "amplifies two very-short games above generic" do
      expect(described_class.ttb_smile(hours(4), hours(4))).to be > described_class.ttb_smile(hours(35), hours(35))
    end

    it "returns 0 for nil or non-positive seconds" do
      expect(described_class.ttb_smile(nil, hours(40))).to eq(0.0)
      expect(described_class.ttb_smile(0, hours(40))).to eq(0.0)
    end
  end

  describe ".era" do
    it "is 100 for the same year and decays with distance" do
      expect(described_class.era(2020, 2020)).to eq(100.0)
      expect(described_class.era(2020, 2013)).to eq(51.0)
      expect(described_class.era(2000, 2020)).to eq(0.0)
    end

    it "returns 0 when either year is nil" do
      expect(described_class.era(nil, 2020)).to eq(0.0)
    end
  end

  describe ".platform_overlap" do
    it "is the Jaccard of the platform arrays" do
      expect(described_class.platform_overlap(%w[PS5 PC], %w[PS5])).to eq(50.0)
      expect(described_class.platform_overlap([], [])).to eq(0.0)
    end
  end

  describe "Pito::Recommendation::Weights.dynamic_embedding_weight" do
    it "is minimal when facets are present and rises (capped) as they go missing" do
      expect(Pito::Recommendation::Weights.dynamic_embedding_weight(1.0)).to eq(0.05)
      expect(Pito::Recommendation::Weights.dynamic_embedding_weight(0.0)).to eq(0.18)
      expect(Pito::Recommendation::Weights.dynamic_embedding_weight(0.5)).to be_within(0.001).of(0.115)
    end
  end
end
