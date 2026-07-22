# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::TitleMatch do
  describe ".tokenize" do
    it "downcases and splits on non-alphanumeric runs" do
      expect(described_class.tokenize("Mortal Kombat 2")).to eq(%w[mortal kombat 2])
    end

    it "returns an empty array for blank input" do
      expect(described_class.tokenize("")).to eq([])
      expect(described_class.tokenize(nil)).to eq([])
    end
  end

  describe ".score_names" do
    it "scores the best-overlapping name among several candidates" do
      score = described_class.score_names(%w[mortal kombat 2 gameplay], [ "Mortal Kombat", "Mortal Kombat 2" ])
      expect(score).to eq([ 1, 3 ]) # anchored, full "mortal kombat 2" run
    end

    it "returns nil when nothing overlaps at all" do
      expect(described_class.score_names(%w[unrelated words], [ "Mortal Kombat" ])).to be_nil
    end
  end

  describe ".contains_name?" do
    context "multi-token name" do
      it "is true when the full token sequence is present contiguously" do
        zone = described_class.tokenize("let's play Mortal Kombat 2 tonight")
        expect(described_class.contains_name?(zone, "Mortal Kombat 2")).to be(true)
      end

      it "is false when only part of the name is present" do
        zone = described_class.tokenize("let's play Mortal tonight")
        expect(described_class.contains_name?(zone, "Mortal Kombat 2")).to be(false)
      end

      it "is false when the name's tokens are present but reordered" do
        zone = described_class.tokenize("kombat mortal 2")
        expect(described_class.contains_name?(zone, "Mortal Kombat 2")).to be(false)
      end

      it "is false when the name's tokens are present but not contiguous" do
        zone = described_class.tokenize("mortal vs kombat 2")
        expect(described_class.contains_name?(zone, "Mortal Kombat 2")).to be(false)
      end
    end

    context "position within the zone" do
      it "is true when the run anchors the start of the zone" do
        zone = described_class.tokenize("Mortal Kombat 2 gameplay highlights")
        expect(described_class.contains_name?(zone, "Mortal Kombat 2")).to be(true)
      end

      it "is true when the run sits in the middle of the zone" do
        zone = described_class.tokenize("stream vod Mortal Kombat 2 gameplay")
        expect(described_class.contains_name?(zone, "Mortal Kombat 2")).to be(true)
      end

      it "is true when the run ends the zone" do
        zone = described_class.tokenize("stream vod Mortal Kombat 2")
        expect(described_class.contains_name?(zone, "Mortal Kombat 2")).to be(true)
      end
    end

    context "single-token name" do
      it "is true when the single token is present anywhere in the zone" do
        zone = described_class.tokenize("today we play Tetris again")
        expect(described_class.contains_name?(zone, "Tetris")).to be(true)
      end

      it "is false when the single token is absent" do
        zone = described_class.tokenize("today we play chess again")
        expect(described_class.contains_name?(zone, "Tetris")).to be(false)
      end
    end

    context "edge cases" do
      it "is false for a blank name against a non-empty zone" do
        zone = described_class.tokenize("Mortal Kombat 2")
        expect(described_class.contains_name?(zone, "")).to be(false)
        expect(described_class.contains_name?(zone, nil)).to be(false)
      end

      it "is false for any name against an empty zone" do
        expect(described_class.contains_name?([], "Mortal Kombat")).to be(false)
      end

      it "is false when both the name and the zone are empty" do
        expect(described_class.contains_name?([], "")).to be(false)
      end

      it "is case-insensitive, following the shared tokenizer's normalization" do
        zone = described_class.tokenize("MORTAL KOMBAT 2")
        expect(described_class.contains_name?(zone, "mortal kombat 2")).to be(true)
      end
    end
  end
end
