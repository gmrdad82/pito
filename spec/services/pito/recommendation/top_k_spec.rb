# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::TopK do
  def items(*scores)
    scores.each_with_index.map { |s, i| { id: i, score: s } }
  end

  describe ".call" do
    context "basic K selection" do
      it "returns at most K items" do
        result = described_class.call(items: items(0.9, 0.8, 0.7, 0.6), k: 2)
        expect(result.size).to eq(2)
      end

      it "returns items sorted descending by score" do
        result = described_class.call(items: items(0.3, 0.9, 0.6), k: 3)
        expect(result.map { |i| i[:score] }).to eq([ 0.9, 0.6, 0.3 ])
      end

      it "returns all items when k exceeds the item count" do
        result = described_class.call(items: items(0.5, 0.2), k: 10)
        expect(result.size).to eq(2)
      end

      it "returns an empty array for an empty input" do
        result = described_class.call(items: [], k: 5)
        expect(result).to eq([])
      end

      it "returns an empty array when k is 0" do
        result = described_class.call(items: items(0.9, 0.8), k: 0)
        expect(result).to eq([])
      end
    end

    context "score threshold" do
      it "excludes items below the threshold" do
        result = described_class.call(items: items(0.9, 0.5, 0.1), k: 10, threshold: 0.5)
        scores = result.map { |i| i[:score] }
        expect(scores).to all(be >= 0.5)
        expect(scores).not_to include(0.1)
      end

      it "returns empty when no items meet the threshold" do
        result = described_class.call(items: items(0.3, 0.2), k: 5, threshold: 0.9)
        expect(result).to eq([])
      end

      it "includes items exactly at the threshold boundary" do
        result = described_class.call(items: items(0.5, 0.4999), k: 10, threshold: 0.5)
        expect(result.map { |i| i[:score] }).to include(0.5)
        expect(result.map { |i| i[:score] }).not_to include(0.4999)
      end

      it "nil threshold applies no floor (returns all items up to k)" do
        result = described_class.call(items: items(0.9, 0.01), k: 10, threshold: nil)
        expect(result.size).to eq(2)
      end
    end

    context "ordering invariants" do
      it "preserves top-k in descending order regardless of input order" do
        shuffled = items(0.1, 0.9, 0.4, 0.7, 0.2)
        result   = described_class.call(items: shuffled, k: 3)
        expect(result.map { |i| i[:score] }).to eq([ 0.9, 0.7, 0.4 ])
      end

      it "handles equal scores without raising" do
        equal_items = [ { id: 1, score: 0.5 }, { id: 2, score: 0.5 }, { id: 3, score: 0.5 } ]
        expect { described_class.call(items: equal_items, k: 2) }.not_to raise_error
      end

      it "returns the correct item hashes (id preserved)" do
        result = described_class.call(items: items(0.2, 0.8), k: 1)
        expect(result.first[:id]).to eq(1) # id=1 has score 0.8
      end
    end
  end
end
