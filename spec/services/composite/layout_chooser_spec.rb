require "rails_helper"

RSpec.describe Composite::LayoutChooser do
  describe ".choose" do
    it "raises ArgumentError on 0" do
      expect { described_class.choose(0) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError on negative" do
      expect { described_class.choose(-1) }.to raise_error(ArgumentError)
    end

    it "raises ArgumentError on non-integer input" do
      expect { described_class.choose("3") }.to raise_error(ArgumentError)
    end

    it "returns Single for 1" do
      expect(described_class.choose(1)).to eq(Composite::Layout::Single)
    end

    it "returns Pair for 2" do
      expect(described_class.choose(2)).to eq(Composite::Layout::Pair)
    end

    it "returns Netflix for 3" do
      expect(described_class.choose(3)).to eq(Composite::Layout::Netflix)
    end

    it "returns Quad for 4" do
      expect(described_class.choose(4)).to eq(Composite::Layout::Quad)
    end

    it "returns NineGrid for 5" do
      expect(described_class.choose(5)).to eq(Composite::Layout::NineGrid)
    end

    it "returns NineGrid for 9" do
      expect(described_class.choose(9)).to eq(Composite::Layout::NineGrid)
    end

    it "returns NineGridWithOverflow for 10" do
      expect(described_class.choose(10)).to eq(Composite::Layout::NineGridWithOverflow)
    end

    it "returns NineGridWithOverflow for 100" do
      expect(described_class.choose(100)).to eq(Composite::Layout::NineGridWithOverflow)
    end
  end
end
