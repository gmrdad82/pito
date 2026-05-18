require "rails_helper"

# `Composite::Layout::SixGrid` — 6 members; 3 columns × 2 rows of
# (100×200) tiles on the 300×400 canvas.
RSpec.describe Composite::Layout::SixGrid do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'six_grid'" do
    expect(described_class.layout_name).to eq("six_grid")
  end

  it "exposes 6 cells (3 columns × 2 rows of thirds-by-halves)" do
    cells = described_class.cells
    third = 1.0 / 3.0
    expect(cells.size).to eq(6)
    # Top row
    expect(cells[0][:y]).to eq(0.0)
    expect(cells[0][:w]).to be_within(0.0001).of(third)
    expect(cells[0][:h]).to eq(0.5)
    expect(cells[2][:x]).to be_within(0.0001).of(2.0 * third)
    # Bot row
    expect(cells[3][:y]).to eq(0.5)
    expect(cells[5][:x]).to be_within(0.0001).of(2.0 * third)
  end

  it "covers the full unit square (∑w*h ≈ 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from 6 tiles" do
    out = described_class.compose(Array.new(6) { tile })
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError on the wrong tile count" do
    expect { described_class.compose(Array.new(5) { tile }) }.to raise_error(ArgumentError, /6 tiles/)
    expect { described_class.compose(Array.new(7) { tile }) }.to raise_error(ArgumentError)
  end
end
