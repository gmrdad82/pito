require "rails_helper"

# `Composite::CellMap` — single source of truth for "where do the cover
# tiles sit on the 0..1 unit square?" Returns the per-layout cell array
# (delegating through `Composite::LayoutChooser`) for the bundle modal
# CSS generator and any other consumer that needs to mirror the
# composite layout in HTML/CSS.
RSpec.describe Composite::CellMap do
  describe ".for(N) defensive guards" do
    it "returns [] for 0 (defensive — LayoutChooser would raise)" do
      expect(described_class.for(0)).to eq([])
    end

    it "returns [] for negative integers" do
      expect(described_class.for(-1)).to eq([])
      expect(described_class.for(-99)).to eq([])
    end

    it "returns [] for nil" do
      expect(described_class.for(nil)).to eq([])
    end

    it "returns [] for non-integer numeric input (Float, BigDecimal)" do
      expect(described_class.for(3.5)).to eq([])
      expect(described_class.for(1.0)).to eq([])
    end

    it "returns [] for string input" do
      expect(described_class.for("3")).to eq([])
      expect(described_class.for("")).to eq([])
    end
  end

  describe ".for(N) — cell count per layout" do
    it "returns 1 cell for N=1 (Single)" do
      expect(described_class.for(1).size).to eq(1)
    end

    it "returns 2 cells for N=2 (Pair)" do
      expect(described_class.for(2).size).to eq(2)
    end

    it "returns 3 cells for N=3 (Netflix)" do
      expect(described_class.for(3).size).to eq(3)
    end

    it "returns 4 cells for N=4 (Quad)" do
      expect(described_class.for(4).size).to eq(4)
    end

    it "returns 5 cells for N=5 (Netflix5)" do
      expect(described_class.for(5).size).to eq(5)
    end

    it "returns 6 cells for N=6 (SixGrid)" do
      expect(described_class.for(6).size).to eq(6)
    end

    it "returns 7 cells for N=7 (Netflix7)" do
      expect(described_class.for(7).size).to eq(7)
    end

    it "returns 8 cells for N=8 (EightGrid)" do
      expect(described_class.for(8).size).to eq(8)
    end

    it "returns 9 cells for N=9 (NineGrid)" do
      expect(described_class.for(9).size).to eq(9)
    end

    it "returns 9 cells for N=10 (NineGridWithOverflow — caps at 9 visible)" do
      # +N overflow is HTML-overlay, not a cell.
      expect(described_class.for(10).size).to eq(9)
    end

    it "returns 9 cells for arbitrarily large N (still capped at 9 via overflow)" do
      expect(described_class.for(50).size).to eq(9)
      expect(described_class.for(1_000).size).to eq(9)
    end
  end

  describe ".for(N) — invariants on each cell" do
    [ 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 25 ].each do |n|
      it "returns cells with x/y/w/h floats in 0..1 for N=#{n}" do
        described_class.for(n).each do |cell|
          expect(cell).to include(:x, :y, :w, :h)
          [ :x, :y, :w, :h ].each do |k|
            expect(cell[k]).to be_a(Numeric), "expected #{k} numeric in #{cell.inspect}"
            expect(cell[k]).to be_between(0.0, 1.0).inclusive
          end
          # Cell must stay within the unit square (right/bottom edges ≤ 1).
          expect(cell[:x] + cell[:w]).to be <= 1.0 + 0.0001
          expect(cell[:y] + cell[:h]).to be <= 1.0 + 0.0001
        end
      end

      it "cells sum to the full unit square for N=#{n}" do
        coverage = described_class.for(n).sum { |c| c[:w] * c[:h] }
        expect(coverage).to be_within(0.0001).of(1.0)
      end
    end
  end

  describe "delegation to LayoutChooser" do
    it "returns the same array object as the chosen layout's .cells" do
      expect(described_class.for(1)).to equal(Composite::Layout::Single.cells)
      expect(described_class.for(4)).to equal(Composite::Layout::Quad.cells)
      expect(described_class.for(5)).to equal(Composite::Layout::Netflix5.cells)
      expect(described_class.for(6)).to equal(Composite::Layout::SixGrid.cells)
      expect(described_class.for(7)).to equal(Composite::Layout::Netflix7.cells)
      expect(described_class.for(8)).to equal(Composite::Layout::EightGrid.cells)
    end

    it "uses NineGridWithOverflow cells (=NineGrid cells) for N>=10" do
      expect(described_class.for(10)).to equal(Composite::Layout::NineGridWithOverflow.cells)
      # Overflow cells are NineGrid cells.
      expect(described_class.for(10)).to equal(Composite::Layout::NineGrid::CELLS)
    end
  end
end
