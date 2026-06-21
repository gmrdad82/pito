# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::Trend, type: :service do
  describe ".for" do
    context "when previous is nil" do
      it "returns :none" do
        expect(described_class.for(current: 100, previous: nil)).to eq(:none)
      end
    end

    context "when previous is zero" do
      it "returns :none" do
        expect(described_class.for(current: 50, previous: 0)).to eq(:none)
      end

      it "returns :none even when current is also zero" do
        expect(described_class.for(current: 0, previous: 0)).to eq(:none)
      end
    end

    context "with default 3% band" do
      it "returns :up when current is clearly above previous" do
        expect(described_class.for(current: 110, previous: 100)).to eq(:up)
      end

      it "returns :down when current is clearly below previous" do
        expect(described_class.for(current: 90, previous: 100)).to eq(:down)
      end

      it "returns :steady when change is within the band (1%)" do
        expect(described_class.for(current: 101, previous: 100)).to eq(:steady)
      end

      it "returns :steady when change is exactly at the band boundary (3%)" do
        expect(described_class.for(current: 103, previous: 100)).to eq(:steady)
      end

      it "returns :steady when change is exactly at the negative band boundary (-3%)" do
        expect(described_class.for(current: 97, previous: 100)).to eq(:steady)
      end

      it "returns :up when change is just above the band (4%)" do
        expect(described_class.for(current: 104, previous: 100)).to eq(:up)
      end

      it "returns :down when change is just below the negative band (-4%)" do
        expect(described_class.for(current: 96, previous: 100)).to eq(:down)
      end
    end

    context "with a custom band" do
      it "returns :steady within a wider 10% band" do
        expect(described_class.for(current: 106, previous: 100, band: 0.10)).to eq(:steady)
      end

      it "returns :up when change exceeds the wider band (11%)" do
        expect(described_class.for(current: 111, previous: 100, band: 0.10)).to eq(:up)
      end

      it "returns :up with a tight 1% band when change is 2%" do
        expect(described_class.for(current: 102, previous: 100, band: 0.01)).to eq(:up)
      end
    end

    context "with large values" do
      it "handles large subscriber counts correctly" do
        expect(described_class.for(current: 1_050_000, previous: 1_000_000)).to eq(:up)
        expect(described_class.for(current: 950_000, previous: 1_000_000)).to eq(:down)
        expect(described_class.for(current: 1_010_000, previous: 1_000_000)).to eq(:steady)
      end
    end

    context "with zero current" do
      it "returns :down when current is zero and previous is positive" do
        expect(described_class.for(current: 0, previous: 100)).to eq(:down)
      end
    end
  end
end
