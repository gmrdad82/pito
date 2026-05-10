require "rails_helper"

RSpec.describe Composite::Checksum do
  describe ".compute" do
    it "returns a 64-char hex string" do
      result = described_class.compute(%w[a b], "pair")
      expect(result).to match(/\A[a-f0-9]{64}\z/)
    end

    it "is invariant under input order (sorts before hashing)" do
      a = described_class.compute(%w[b a], "pair")
      b = described_class.compute(%w[a b], "pair")
      expect(a).to eq(b)
    end

    it "returns a deterministic hash for empty input" do
      a = described_class.compute([], "single")
      b = described_class.compute([], "single")
      expect(a).to eq(b)
      expect(a).to match(/\A[a-f0-9]{64}\z/)
    end

    it "differs when only the layout differs" do
      a = described_class.compute(%w[a], "single")
      b = described_class.compute(%w[a], "pair")
      expect(a).not_to eq(b)
    end

    it "differs when the image_ids differ" do
      a = described_class.compute(%w[a b], "pair")
      b = described_class.compute(%w[a c], "pair")
      expect(a).not_to eq(b)
    end

    it "filters nil entries before hashing" do
      a = described_class.compute([ "a", nil, "b" ], "pair")
      b = described_class.compute(%w[a b], "pair")
      expect(a).to eq(b)
    end
  end
end
