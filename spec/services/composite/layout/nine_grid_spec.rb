require "rails_helper"

# `Composite::Layout::NineGrid` — exactly 9 members; 3×3 grid on the
# 300×400 canvas. The blank-cell helper survives in the builder so
# `NineGridWithOverflow` can degenerate gracefully.
RSpec.describe Composite::Layout::NineGrid do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'nine_grid'" do
    expect(described_class.layout_name).to eq("nine_grid")
  end

  it "exposes 9 cells (3×3 row-major thirds)" do
    cells = described_class.cells
    expect(cells.size).to eq(9)
    third = 1.0 / 3.0
    expect(cells[0]).to eq({ x: 0.0,         y: 0.0,         w: third, h: third })
    expect(cells[4]).to eq({ x: third,       y: third,       w: third, h: third })
    expect(cells[8]).to eq({ x: 2.0 * third, y: 2.0 * third, w: third, h: third })
  end

  it "covers the full unit square (∑w*h ≈ 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from 9 tiles" do
    out = described_class.compose(Array.new(9) { tile })
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError on tile count != 9" do
    expect { described_class.compose(Array.new(8) { tile }) }.to raise_error(ArgumentError, /9 tiles/)
    expect { described_class.compose(Array.new(10) { tile }) }.to raise_error(ArgumentError)
  end
end
