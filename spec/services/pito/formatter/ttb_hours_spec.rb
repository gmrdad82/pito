# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Formatter::TtbHours do
  describe ".call" do
    # ── nil / zero / negative → em-dash ─────────────────────────────────────
    it "returns em-dash for nil" do
      expect(described_class.call(nil)).to eq("—")
    end

    it "returns em-dash for 0" do
      expect(described_class.call(0)).to eq("—")
    end

    it "returns em-dash for negative values" do
      expect(described_class.call(-3600)).to eq("—")
      expect(described_class.call(-1)).to eq("—")
    end

    # ── Rounding: half-up so 59m rounds to 1h ───────────────────────────────
    it "rounds 3540s (59m) up to 1h" do
      expect(described_class.call(3540)).to eq("1h")
    end

    it "rounds 1800s (30m) up to 1h" do
      expect(described_class.call(1800)).to eq("1h")
    end

    it "rounds 1799s (29m59s) down to 0h — outputs '0h' (no post-round guard)" do
      # 1799 / 3600 = ~0.4997 → rounds to 0 → "0h"
      # The em-dash guard is only on the raw input, not the rounded result.
      expect(described_class.call(1799)).to eq("0h")
    end

    # ── Exact whole hours ────────────────────────────────────────────────────
    it "returns '1h' for exactly 3600s" do
      expect(described_class.call(3600)).to eq("1h")
    end

    it "returns '2h' for exactly 7200s" do
      expect(described_class.call(7200)).to eq("2h")
    end

    it "returns '10h' for 36000s" do
      expect(described_class.call(36_000)).to eq("10h")
    end

    it "returns '100h' for 360000s" do
      expect(described_class.call(360_000)).to eq("100h")
    end

    # ── String coercion ──────────────────────────────────────────────────────
    it "coerces a string integer via to_i" do
      expect(described_class.call("7200")).to eq("2h")
    end

    it "returns em-dash for an empty string (coerces to 0)" do
      expect(described_class.call("")).to eq("—")
    end

    # ── Format shape ─────────────────────────────────────────────────────────
    it "always outputs '<N>h' with no decimal for valid inputs" do
      [ 3600, 7200, 9000, 36_000 ].each do |s|
        result = described_class.call(s)
        expect(result).to match(/\A\d+h\z/), "unexpected for #{s}: #{result.inspect}"
      end
    end

    it "uses EM_DASH constant (not a plain hyphen)" do
      expect(described_class::EM_DASH).to eq("—")
    end
  end
end
