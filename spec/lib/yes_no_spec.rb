require "rails_helper"

RSpec.describe YesNo do
  describe ".to_yes_no" do
    it "returns 'yes' for true" do
      expect(described_class.to_yes_no(true)).to eq("yes")
    end

    it "returns 'no' for false" do
      expect(described_class.to_yes_no(false)).to eq("no")
    end

    it "returns 'no' for nil (nil is falsy)" do
      expect(described_class.to_yes_no(nil)).to eq("no")
    end
  end

  describe ".from_yes_no" do
    it "returns true for 'yes'" do
      expect(described_class.from_yes_no("yes")).to be true
    end

    it "is case-insensitive" do
      expect(described_class.from_yes_no("Yes")).to be true
      expect(described_class.from_yes_no("YES")).to be true
    end

    it "returns false for 'no'" do
      expect(described_class.from_yes_no("no")).to be false
    end

    it "returns false for non-yes/no strings (caller should validate first)" do
      expect(described_class.from_yes_no("true")).to be false
      expect(described_class.from_yes_no("1")).to be false
      expect(described_class.from_yes_no("")).to be false
      expect(described_class.from_yes_no(nil)).to be false
    end
  end

  describe ".yes_no?" do
    it "is true only for the literal strings 'yes' and 'no'" do
      expect(described_class.yes_no?("yes")).to be true
      expect(described_class.yes_no?("no")).to be true
      expect(described_class.yes_no?("YES")).to be true
      expect(described_class.yes_no?("No")).to be true
    end

    it "is false for legacy or boolean-like values" do
      expect(described_class.yes_no?(true)).to be false
      expect(described_class.yes_no?(false)).to be false
      expect(described_class.yes_no?("true")).to be false
      expect(described_class.yes_no?("false")).to be false
      expect(described_class.yes_no?("1")).to be false
      expect(described_class.yes_no?("0")).to be false
      expect(described_class.yes_no?("on")).to be false
      expect(described_class.yes_no?("")).to be false
      expect(described_class.yes_no?(nil)).to be false
    end
  end
end
