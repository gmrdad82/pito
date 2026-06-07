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
end
