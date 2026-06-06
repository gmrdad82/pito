# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::WeightedBlend do
  describe ".blend" do
    context "single signal" do
      it "returns the score weighted by the single weight" do
        signals = { 1 => { relevance: 0.8 } }
        result  = described_class.blend(signals: signals, weights: { relevance: 1.0 })
        expect(result).to contain_exactly({ id: 1, score: be_within(0.001).of(0.8) })
      end

      it "returns 0.0 when the weight for a signal is 0" do
        signals = { 1 => { relevance: 0.9 } }
        result  = described_class.blend(signals: signals, weights: { relevance: 0.0 })
        expect(result.first[:score]).to be_within(0.001).of(0.0)
      end
    end

    context "multiple signals" do
      let(:signals) do
        {
          42 => { relevance: 0.8, popularity: 0.4 },
          99 => { relevance: 0.2, popularity: 1.0 }
        }
      end

      let(:weights) { { relevance: 0.7, popularity: 0.3 } }

      it "returns one hash per candidate id" do
        result = described_class.blend(signals: signals, weights: weights)
        expect(result.map { |r| r[:id] }).to match_array([ 42, 99 ])
      end

      it "computes 0.7*0.8 + 0.3*0.4 = 0.68 for id 42" do
        result = described_class.blend(signals: signals, weights: weights)
        r42    = result.find { |r| r[:id] == 42 }
        expect(r42[:score]).to be_within(0.001).of(0.68)
      end

      it "computes 0.7*0.2 + 0.3*1.0 = 0.44 for id 99" do
        result = described_class.blend(signals: signals, weights: weights)
        r99    = result.find { |r| r[:id] == 99 }
        expect(r99[:score]).to be_within(0.001).of(0.44)
      end
    end

    context "missing signal in weights" do
      it "treats a missing weight as 0 (does not raise)" do
        signals = { 1 => { unknown_signal: 0.9, relevance: 0.5 } }
        weights = { relevance: 1.0 }  # unknown_signal not in weights
        result  = described_class.blend(signals: signals, weights: weights)
        expect(result.first[:score]).to be_within(0.001).of(0.5)
      end
    end

    context "empty inputs" do
      it "returns an empty array for empty signals" do
        result = described_class.blend(signals: {}, weights: { relevance: 1.0 })
        expect(result).to eq([])
      end

      it "returns 0.0 scores when weights is empty" do
        signals = { 1 => { relevance: 0.9 } }
        result  = described_class.blend(signals: signals, weights: {})
        expect(result.first[:score]).to eq(0.0)
      end
    end

    context "weights summing to 1.0" do
      it "a perfectly-scored candidate returns 1.0 when all signals are 1.0" do
        signals = { 7 => { a: 1.0, b: 1.0 } }
        weights = { a: 0.5, b: 0.5 }
        result  = described_class.blend(signals: signals, weights: weights)
        expect(result.first[:score]).to be_within(0.001).of(1.0)
      end
    end
  end
end
