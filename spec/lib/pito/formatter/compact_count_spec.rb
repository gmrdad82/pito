# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::CompactCount do
  it "returns em-dash for nil" do
    expect(described_class.call(nil)).to eq("—")
  end

  it "returns 0 for 0" do
    expect(described_class.call(0)).to eq("0")
  end

  it "returns raw integer below 1_000" do
    expect(described_class.call(42)).to eq("42")
    expect(described_class.call(999)).to eq("999")
  end

  # Owner rule: the compact value rounds DOWN, never up — it must never overstate
  # the real count (the true number is always ≥ what's shown).
  describe "rounds down (never overstates)" do
    it "shows 2,259 as 2.2K (not 2.3K)" do
      expect(described_class.call(2_259)).to eq("2.2K")
    end

    it "shows 9,999 as 9.9K (not 10K)" do
      expect(described_class.call(9_999)).to eq("9.9K")
    end

    it "shows 47,500 as 47K (not 48K)" do
      expect(described_class.call(47_500)).to eq("47K")
    end

    it "shows 999,999,999 as 999M (not 1B)" do
      expect(described_class.call(999_999_999)).to eq("999M")
    end
  end

  describe "K tier" do
    it "renders 1-decimal K below 10K (floored)" do
      expect(described_class.call(1_000)).to eq("1K")
      expect(described_class.call(1_500)).to eq("1.5K")
      expect(described_class.call(2_300)).to eq("2.3K")
      expect(described_class.call(9_950)).to eq("9.9K")
    end

    it "renders integer K at 10K+ (floored)" do
      expect(described_class.call(10_000)).to eq("10K")
      expect(described_class.call(47_900)).to eq("47K")
    end
  end

  describe "M tier" do
    it "renders 1-decimal M below 10M (floored)" do
      expect(described_class.call(1_000_000)).to eq("1M")
      expect(described_class.call(2_300_000)).to eq("2.3M")
    end

    it "renders integer M at 10M+ (floored)" do
      expect(described_class.call(10_000_000)).to eq("10M")
      expect(described_class.call(47_000_000)).to eq("47M")
    end
  end

  describe "B tier" do
    it "renders 1-decimal B below 10B (floored)" do
      expect(described_class.call(1_000_000_000)).to eq("1B")
      expect(described_class.call(2_300_000_000)).to eq("2.3B")
    end

    it "renders integer B at 10B+ (floored)" do
      expect(described_class.call(10_000_000_000)).to eq("10B")
      expect(described_class.call(47_000_000_000)).to eq("47B")
    end
  end
end
