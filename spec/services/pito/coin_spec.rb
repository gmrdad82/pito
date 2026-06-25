# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Coin do
  describe ".tier" do
    # ── unpriced (nil) vs free (explicit 0) — distinct states ───────────────
    it "is :unpriced for nil (unset/unknown)" do
      expect(described_class.tier(nil)).to eq(:unpriced)
    end

    it "is :free for an explicit 0 / 0.0" do
      expect(described_class.tier(0)).to eq(:free)
      expect(described_class.tier(BigDecimal("0.00"))).to eq(:free)
    end

    it "treats a (forbidden) negative as :unpriced, not free" do
      expect(described_class.tier(BigDecimal("-5.00"))).to eq(:unpriced)
    end

    # ── tier boundaries (inclusive upper bounds 9.99 / 29.99 / 59.99 / 79.99) ─
    it "tier 1 up to and including 9.99" do
      expect(described_class.tier(BigDecimal("4.99"))).to eq(1)
      expect(described_class.tier(BigDecimal("9.99"))).to eq(1)
    end

    it "tier 2 above 9.99 up to 29.99" do
      expect(described_class.tier(BigDecimal("10.00"))).to eq(2)
      expect(described_class.tier(BigDecimal("19.99"))).to eq(2)
      expect(described_class.tier(BigDecimal("29.99"))).to eq(2)
    end

    it "tier 3 above 29.99 up to 59.99" do
      expect(described_class.tier(BigDecimal("30.00"))).to eq(3)
      expect(described_class.tier(BigDecimal("49.99"))).to eq(3)
      expect(described_class.tier(BigDecimal("59.99"))).to eq(3)
    end

    it "tier 4 above 59.99 up to 79.99 (new-AAA full price)" do
      expect(described_class.tier(BigDecimal("60.00"))).to eq(4)
      expect(described_class.tier(BigDecimal("69.99"))).to eq(4)
      expect(described_class.tier(BigDecimal("79.99"))).to eq(4)
    end

    it "tier 5 above 79.99 (premium / collector)" do
      expect(described_class.tier(BigDecimal("80.00"))).to eq(5)
      expect(described_class.tier(BigDecimal("99.99"))).to eq(5)
      expect(described_class.tier(BigDecimal("199.99"))).to eq(5)
    end

    it "handles round (non-.99) prices robustly" do
      expect(described_class.tier(BigDecimal("45.00"))).to eq(3)
      expect(described_class.tier(BigDecimal("60.00"))).to eq(4)
    end

    it "accepts a plain Numeric, not just BigDecimal" do
      expect(described_class.tier(59.99)).to eq(3)
      expect(described_class.tier(80)).to eq(5)
    end
  end

  describe ".free?" do
    it "is true only for an explicit 0 (not nil)" do
      expect(described_class.free?(0)).to be(true)
      expect(described_class.free?(BigDecimal("0.00"))).to be(true)
      expect(described_class.free?(nil)).to be(false)
      expect(described_class.free?(BigDecimal("9.99"))).to be(false)
    end
  end

  describe ".unpriced?" do
    it "is true only for nil (not an explicit 0)" do
      expect(described_class.unpriced?(nil)).to be(true)
      expect(described_class.unpriced?(0)).to be(false)
      expect(described_class.unpriced?(BigDecimal("9.99"))).to be(false)
    end
  end

  describe ".coin_count" do
    it "is 0 when unpriced/free, else the tier (1..5)" do
      expect(described_class.coin_count(nil)).to eq(0)
      expect(described_class.coin_count(0)).to eq(0)
      expect(described_class.coin_count(BigDecimal("9.99"))).to eq(1)
      expect(described_class.coin_count(BigDecimal("59.99"))).to eq(3)
      expect(described_class.coin_count(BigDecimal("99.99"))).to eq(5)
    end
  end
end
