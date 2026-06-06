# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Recommendation::HmsScorer do
  describe ".bucket" do
    context ":bad bucket (score < 0.2)" do
      it "returns :bad for 0.0" do
        expect(described_class.bucket(score: 0.0)).to eq(:bad)
      end

      it "returns :bad for 0.19" do
        expect(described_class.bucket(score: 0.19)).to eq(:bad)
      end

      it "returns :bad just below BAD_MAX boundary (0.199...)" do
        expect(described_class.bucket(score: 0.1999)).to eq(:bad)
      end
    end

    context ":weak bucket (0.2 <= score < 0.4)" do
      it "returns :weak at exactly 0.2" do
        expect(described_class.bucket(score: 0.2)).to eq(:weak)
      end

      it "returns :weak at 0.39" do
        expect(described_class.bucket(score: 0.39)).to eq(:weak)
      end
    end

    context ":ok bucket (0.4 <= score < 0.6)" do
      it "returns :ok at exactly 0.4" do
        expect(described_class.bucket(score: 0.4)).to eq(:ok)
      end

      it "returns :ok at 0.59" do
        expect(described_class.bucket(score: 0.59)).to eq(:ok)
      end
    end

    context ":good bucket (0.6 <= score < 0.8)" do
      it "returns :good at exactly 0.6" do
        expect(described_class.bucket(score: 0.6)).to eq(:good)
      end

      it "returns :good at 0.79" do
        expect(described_class.bucket(score: 0.79)).to eq(:good)
      end
    end

    context ":great bucket (score >= 0.8)" do
      it "returns :great at exactly 0.8" do
        expect(described_class.bucket(score: 0.8)).to eq(:great)
      end

      it "returns :great at 1.0" do
        expect(described_class.bucket(score: 1.0)).to eq(:great)
      end

      it "returns :great above 1.0 (no upper clamp in scorer)" do
        expect(described_class.bucket(score: 1.5)).to eq(:great)
      end
    end

    context "boundary values" do
      it "bucket constants match expected values" do
        expect(described_class::BAD_MAX).to eq(0.2)
        expect(described_class::WEAK_MAX).to eq(0.4)
        expect(described_class::OK_MAX).to eq(0.6)
        expect(described_class::GOOD_MAX).to eq(0.8)
      end

      it "returns a symbol from the known set for every valid 0..1 value" do
        known = %i[bad weak ok good great]
        [ 0.0, 0.1, 0.2, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8, 0.9, 1.0 ].each do |s|
          expect(known).to include(described_class.bucket(score: s))
        end
      end
    end
  end
end
