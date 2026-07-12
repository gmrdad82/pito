# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Themes::Oklch do
  describe "round-trip" do
    exact_round_trip_hexes = %w[
      #b967ff
      #1a0b2e
      #5170ff
      #ffffff
      #000000
      #ff2e63
    ]

    exact_round_trip_hexes.each do |hex|
      it "round-trips #{hex} through from_hex/to_hex with 0 LSB drift" do
        lch = described_class.from_hex(hex)

        expect(described_class.to_hex(*lch)).to eq(hex)
      end
    end
  end

  describe ".from_hex" do
    it "reports white as l≈1.0, c≈0, h=0.0" do
      l, c, h = described_class.from_hex("#ffffff")

      expect(l).to be_within(1e-4).of(1.0)
      expect(c).to be < 1e-4
      expect(h).to eq(0.0)
    end

    it "reports black as l≈0, c≈0, h=0.0" do
      l, c, h = described_class.from_hex("#000000")

      expect(l).to be < 1e-4
      expect(c).to be < 1e-4
      expect(h).to eq(0.0)
    end

    it "reports achromatic greys with h=0.0" do
      _l, _c, h = described_class.from_hex("#808080")

      expect(h).to eq(0.0)
    end
  end

  describe "delta/apply" do
    it "reconstructs the target hex exactly when applying the measured delta (#1a0b2e -> #b967ff)" do
      delta = described_class.delta("#1a0b2e", "#b967ff")

      expect(described_class.apply("#1a0b2e", delta)).to eq("#b967ff")
    end

    it "reconstructs the target hex exactly when applying the measured delta (#1a0b2e -> #5170ff)" do
      delta = described_class.delta("#1a0b2e", "#5170ff")

      expect(described_class.apply("#1a0b2e", delta)).to eq("#5170ff")
    end

    it "returns the shortest signed hue arc across the 0/360 boundary" do
      from_hex = "#ff00c3"
      to_hex = "#ff2e63"

      _from_l, _from_c, from_h = described_class.from_hex(from_hex)
      _to_l, _to_c, to_h = described_class.from_hex(to_hex)
      naive_diff = to_h - from_h

      # sanity: the two hues straddle the 0/360 seam, so the naive (unwrapped)
      # difference goes the long way around
      expect(naive_diff.abs).to be > 180

      _dl, _dc, dh = described_class.delta(from_hex, to_hex)

      expect(dh.abs).to be < 180
      expect(described_class.apply(from_hex, described_class.delta(from_hex, to_hex))).to eq(to_hex)
    end
  end

  describe "gamut clamping" do
    it "reduces chroma to fit sRGB while holding l/h, without raising" do
      hex = nil

      expect { hex = described_class.to_hex(0.95, 0.35, 330) }.not_to raise_error
      expect(hex).to match(/\A#[0-9a-f]{6}\z/)

      l, _c, h = described_class.from_hex(hex)

      expect(l).to be_within(0.02).of(0.95)
      expect(h).to be_within(2.0).of(330)
    end

    it "clamps l into 0..1 and floors c at 0 when applying an out-of-range delta" do
      hex = nil

      expect { hex = described_class.apply("#ffffff", [ 0.5, -1.0, 0.0 ]) }.not_to raise_error
      expect(hex).to match(/\A#[0-9a-f]{6}\z/)
    end
  end
end
