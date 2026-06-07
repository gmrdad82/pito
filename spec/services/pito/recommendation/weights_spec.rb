# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::Weights do
  it "blend weights sum to 1.0" do
    expect(described_class::BLEND.values.sum).to be_within(1e-9).of(1.0)
  end

  it "ranks the signal weights score > developer > publisher" do
    expect(described_class::S).to be > described_class::D
    expect(described_class::D).to be > described_class::P
  end

  it "keeps embedding the largest and genre second" do
    expect(described_class::E).to be > described_class::G
    expect(described_class::G).to be > described_class::S
  end

  describe ".blend" do
    it "returns 100 when every sub-score is 100" do
      expect(described_class.blend(e: 100, g: 100, s: 100, d: 100, p: 100)).to eq(100)
    end

    it "returns 0 for an all-zero breakdown" do
      expect(described_class.blend(e: 0, g: 0, s: 0, d: 0, p: 0)).to eq(0)
    end

    it "weights embedding-only at 45" do
      expect(described_class.blend(e: 100)).to eq(45)
    end

    it "weights a same-developer-only match (D) above a same-publisher-only match (P)" do
      dev_only = described_class.blend(d: 100)
      pub_only = described_class.blend(p: 100)
      expect(dev_only).to be > pub_only
      expect(dev_only).to eq(12)
      expect(pub_only).to eq(8)
    end

    it "weights a close-score-only match (S) above developer and publisher" do
      score_only = described_class.blend(s: 100)
      expect(score_only).to eq(15)
      expect(score_only).to be > described_class.blend(d: 100)
    end

    it "treats missing keys as zero" do
      expect(described_class.blend(g: 100)).to eq(20)
    end
  end
end
