# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::FootageHours do
  describe ".call" do
    # ── nil / zero / negative → "0h" (footage always has 0 as its fallback) ──
    it "returns 0h for nil" do
      expect(described_class.call(nil)).to eq("0h")
    end

    it "returns 0h for 0" do
      expect(described_class.call(BigDecimal("0.0"))).to eq("0h")
      expect(described_class.call(0)).to eq("0h")
    end

    it "returns 0h for negative values" do
      expect(described_class.call(BigDecimal("-2.5"))).to eq("0h")
    end

    # ── Whole numbers drop the decimal ──────────────────────────────────────
    it "renders a whole-hour value without the trailing .0" do
      expect(described_class.call(BigDecimal("5.0"))).to eq("5h")
    end

    # ── Halves keep one decimal ─────────────────────────────────────────────
    it "renders a half value with one decimal" do
      expect(described_class.call(BigDecimal("12.5"))).to eq("12.5h")
    end

    it "renders 2.5 hours as '2.5h'" do
      expect(described_class.call(BigDecimal("2.5"))).to eq("2.5h")
    end
  end
end
