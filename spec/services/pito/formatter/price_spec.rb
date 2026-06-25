# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::Price do
  describe ".call" do
    # ── nil / negative → em-dash; explicit 0 → "€0.00" (free is a real amount) ─
    it "returns em-dash for nil (unpriced)" do
      expect(described_class.call(nil)).to eq("—")
    end

    it "renders an explicit 0 as €0.00 (free is mentioned, not hidden)" do
      expect(described_class.call(BigDecimal("0.00"))).to eq("€0.00")
      expect(described_class.call(0)).to eq("€0.00")
    end

    it "returns em-dash for negative values" do
      expect(described_class.call(BigDecimal("-5.00"))).to eq("—")
    end

    # ── € prefix, always two decimals ───────────────────────────────────────
    it "renders with a € prefix and two decimals" do
      expect(described_class.call(BigDecimal("59.99"))).to eq("€59.99")
    end

    it "pads a half value to two decimals" do
      expect(described_class.call(BigDecimal("8.5"))).to eq("€8.50")
    end

    it "pads a whole value to two decimals" do
      expect(described_class.call(120)).to eq("€120.00")
    end

    it "uses EM_DASH constant (not a plain hyphen)" do
      expect(described_class::EM_DASH).to eq("—")
    end

    # ── symbol: false → bare number (coins supply the € in PriceGlyphs) ──────
    it "omits the € when symbol: false" do
      expect(described_class.call(BigDecimal("59.99"), symbol: false)).to eq("59.99")
      expect(described_class.call(120, symbol: false)).to eq("120.00")
    end

    it "renders nil as em-dash and 0 as bare 0.00 with symbol: false" do
      expect(described_class.call(nil, symbol: false)).to eq("—")
      expect(described_class.call(0, symbol: false)).to eq("0.00")
    end
  end

  # ── unpriced? (nil) vs free? (explicit 0 / 0.00) ──────────────────────────
  describe ".unpriced?" do
    it "is true only for nil" do
      expect(described_class.unpriced?(nil)).to be(true)
      expect(described_class.unpriced?(0)).to be(false)
      expect(described_class.unpriced?(BigDecimal("9.99"))).to be(false)
    end
  end

  describe ".free?" do
    it "is true for an explicit 0 / 0.00 (not nil, not positive)" do
      expect(described_class.free?(0)).to be(true)
      expect(described_class.free?(BigDecimal("0.00"))).to be(true)
      expect(described_class.free?(0.0)).to be(true)
      expect(described_class.free?(nil)).to be(false)
      expect(described_class.free?(BigDecimal("9.99"))).to be(false)
    end

    it "is false for non-numeric junk (no raise)" do
      expect(described_class.free?("nope")).to be(false)
    end
  end
end
