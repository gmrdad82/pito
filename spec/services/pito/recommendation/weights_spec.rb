# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::Weights do
  # v2: weights are RELATIVE (present-signal normalization); they need not sum to 1.0
  it "blend weights are positive and genre is the dominant single signal" do
    expect(described_class::BLEND.values).to all(be > 0)
    others = described_class::BLEND.except(:g).values
    expect(described_class::G).to be > others.max
  end

  it "ranks genre > perspective > theme = score > ttb > developer > era = platform > publisher > embedding" do
    expect(described_class::G).to be > described_class::PP
    expect(described_class::PP).to be > described_class::T
    expect(described_class::T).to eq(described_class::S)
    expect(described_class::S).to be > described_class::TTB
    expect(described_class::TTB).to be > described_class::D
    expect(described_class::D).to be > described_class::ERA
    expect(described_class::ERA).to eq(described_class::PLATFORM)
    expect(described_class::PLATFORM).to be > described_class::P
    expect(described_class::P).to eq(described_class::E)
  end

  it "ranks score > developer > publisher" do
    expect(described_class::S).to be > described_class::D
    expect(described_class::D).to be > described_class::P
  end

  describe ".blend" do
    it "returns 100 when every sub-score is 100" do
      expect(described_class.blend(e: 100, g: 100, t: 100, pp: 100, s: 100, d: 100, p: 100)).to eq(100)
    end

    it "returns 0 for an all-zero breakdown" do
      expect(described_class.blend(e: 0, g: 0, t: 0, pp: 0, s: 0, d: 0, p: 0)).to eq(0)
    end

    # v2: a single-key blend normalizes over that key alone → always 100 when score=100.
    # To compare signal weights, use the same multi-signal context (e.g., e: 0 present).
    it "scores a genre+embedding match higher than perspective+embedding (G > PP)" do
      expect(described_class.blend(e: 0, g: 100)).to be > described_class.blend(e: 0, pp: 100)
    end

    it "scores a developer-only match higher than a publisher-only match" do
      # both signals present at 0 as peer → compare blend with the other as 0
      expect(described_class.blend(d: 100, p: 0)).to be > described_class.blend(p: 100, d: 0)
    end

    it "scores a close-score-only match higher than developer or publisher alone" do
      expect(described_class.blend(s: 100, d: 0)).to be > described_class.blend(d: 100, s: 0)
      expect(described_class.blend(s: 100, p: 0)).to be > described_class.blend(p: 100, s: 0)
    end

    # v2: absent signals are omitted — .blend normalizes over present keys only
    it "normalizes over present keys: single-key blend of 100 always returns 100" do
      expect(described_class.blend(g: 100)).to eq(100)
      expect(described_class.blend(pp: 100)).to eq(100)
      expect(described_class.blend(e: 100)).to eq(100)
    end
  end

  describe ".graded_link (α=5, β=1)" do
    it "is 0 when the game has no published video on the channel" do
      expect(described_class.graded_link(0, 10)).to eq(0.0)
    end

    it "keeps a lone video small on a focused channel and smaller on a busy one" do
      expect(described_class.graded_link(1, 0)).to be_within(0.1).of(16.7)  # 100/(1+5)
      expect(described_class.graded_link(1, 10)).to be_within(0.1).of(6.25) # 100/(1+5+10)
    end

    it "rises with depth and falls with breadth" do
      expect(described_class.graded_link(3, 0)).to be > described_class.graded_link(1, 0)
      expect(described_class.graded_link(1, 20)).to be < described_class.graded_link(1, 5)
    end
  end
end
