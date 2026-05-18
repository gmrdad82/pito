require "rails_helper"

# `Composite::Layout::EightGrid` — 8 members; 2 columns × 4 rows of
# (150×100) tiles on the 300×400 canvas.
RSpec.describe Composite::Layout::EightGrid do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'eight_grid'" do
    expect(described_class.layout_name).to eq("eight_grid")
  end

  it "exposes 8 cells (2 columns × 4 rows of half-by-quarter)" do
    cells = described_class.cells
    expect(cells.size).to eq(8)
    # Row 0
    expect(cells[0]).to eq({ x: 0.0, y: 0.0,  w: 0.5, h: 0.25 })
    expect(cells[1]).to eq({ x: 0.5, y: 0.0,  w: 0.5, h: 0.25 })
    # Row 1
    expect(cells[2]).to eq({ x: 0.0, y: 0.25, w: 0.5, h: 0.25 })
    # Row 3 (bottom)
    expect(cells[6]).to eq({ x: 0.0, y: 0.75, w: 0.5, h: 0.25 })
    expect(cells[7]).to eq({ x: 0.5, y: 0.75, w: 0.5, h: 0.25 })
  end

  it "covers the full unit square (∑w*h == 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from 8 tiles" do
    out = described_class.compose(Array.new(8) { tile })
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError on the wrong tile count" do
    expect { described_class.compose(Array.new(7) { tile }) }.to raise_error(ArgumentError, /8 tiles/)
    expect { described_class.compose(Array.new(9) { tile }) }.to raise_error(ArgumentError)
  end
end
