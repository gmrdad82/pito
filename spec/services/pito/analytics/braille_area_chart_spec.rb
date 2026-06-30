# frozen_string_literal: true

require "rails_helper"

RSpec.describe Pito::Analytics::BrailleAreaChart do
  BLANK = "⠀"

  def braille?(str) = str.chars.all? { |c| c.ord >= 0x2800 && c.ord <= 0x28FF }

  describe ".call dimensions" do
    it "returns `rows` strings, each `cols` braille chars wide" do
      out = described_class.call(series: [ 1, 2, 3 ], cols: 10, rows: 4)
      expect(out.size).to eq(4)
      expect(out.map(&:length).uniq).to eq([ 10 ])
      expect(out.all? { |row| braille?(row) }).to be(true)
    end

    it "clamps cols/rows to a minimum of 1" do
      out = described_class.call(series: [ 5 ], cols: 0, rows: 0)
      expect(out.size).to eq(1)
      expect(out.first.length).to eq(1)
    end
  end

  describe "empty / zero input → minimal baseline (not blank)" do
    # BASELINE_DOTS = 1 → only the bottom dot row of each cell fills: dots 7+8
    # (0x40|0x80) → U+28C0 "⣀".
    BASELINE_ROW = "⣀"

    it "draws a minimal baseline on the bottom row for an empty series" do
      out = described_class.call(series: [], cols: 6, rows: 3)
      expect(out[0]).to eq(BLANK * 6)        # upper rows blank
      expect(out[1]).to eq(BLANK * 6)
      expect(out.last).to eq(BASELINE_ROW * 6) # baseline floor
    end

    it "draws the baseline for an all-zero series too (0 is not invisible)" do
      out = described_class.call(series: [ 0, 0, 0 ], cols: 6, rows: 3)
      expect(out.last).to eq(BASELINE_ROW * 6)
      expect(out.first).to eq(BLANK * 6)
    end

    it "floors a 0-day to the baseline within a series that has data" do
      # one tall column + one zero column → the zero column still shows the baseline
      out  = described_class.call(series: [ 10, 0 ], cols: 2, rows: 2, max: 10)
      last = out.last
      expect(last).not_to include(BLANK) # both columns have at least the baseline
    end
  end

  describe "non-zero minimum bump" do
    it "renders at least one dot above the baseline for a tiny positive value" do
      # 1 against max 1000 → scaled = 0 without the min-bump fix; must show a bump.
      out = described_class.call(series: [ 1, 1 ], cols: 4, rows: 2, max: 1000)
      # Every column must be above the pure baseline char (⣀ = U+28C0)
      baseline = "⣀"
      expect(out.last.chars).to all(satisfy { |c| c != baseline })
    end

    it "leaves a genuine zero at the baseline (no false bump for 0)" do
      out = described_class.call(series: [ 0, 0 ], cols: 4, rows: 2, max: 1000)
      baseline = "⣀"
      expect(out.last.chars).to all(eq(baseline))
    end
  end

  describe "fill is bottom-anchored (area chart)" do
    it "fills the FULL height for a flat non-zero series" do
      out = described_class.call(series: [ 5, 5, 5, 5 ], cols: 4, rows: 3)
      # every cell fully filled → U+28FF (all 8 dots)
      expect(out).to all(eq("⣿" * 4))
    end

    it "leaves the TOP empty and fills the BOTTOM for a small value" do
      # value 1 of max 10 over a 4-cell-tall canvas → only the bottom band fills
      out = described_class.call(series: [ 1, 1 ], cols: 2, rows: 4, max: 10)
      expect(out.first).to eq(BLANK * 2)        # top row empty
      expect(out.last).not_to eq(BLANK * 2)     # bottom row has dots
    end
  end

  describe "shape tracks the series" do
    it "rises left→right for an increasing ramp (more filled dots toward the right)" do
      out  = described_class.call(series: [ 0, 10 ], cols: 10, rows: 4, max: 10)
      dots = ->(col) { out.sum { |row| row[col].ord - 0x2800 == 0 ? 0 : 1 } }
      # the rightmost column should carry at least as much fill as the leftmost
      expect(dots.call(9)).to be >= dots.call(0)
      expect(dots.call(9)).to be_positive
    end
  end

  describe "max ceiling" do
    it "uses the series peak when max is nil (peak reaches full height)" do
      out = described_class.call(series: [ 2, 8 ], cols: 6, rows: 2)
      # the peak column (right edge) should reach the very top row
      expect(out.first.chars.last.ord).to be > 0x2800
    end

    it "honours an explicit max above the peak (never reaches full height)" do
      out = described_class.call(series: [ 5, 5 ], cols: 4, rows: 4, max: 100)
      expect(out.first).to eq(BLANK * 4) # 5/100 is tiny → top stays empty
    end
  end
end
