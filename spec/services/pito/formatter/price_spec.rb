# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::Price do
  describe ".call" do
    # ── nil / zero / negative → em-dash ─────────────────────────────────────
    it "returns em-dash for nil (unpriced)" do
      expect(described_class.call(nil)).to eq("—")
    end

    it "returns em-dash for 0" do
      expect(described_class.call(BigDecimal("0.00"))).to eq("—")
      expect(described_class.call(0)).to eq("—")
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
  end
end
