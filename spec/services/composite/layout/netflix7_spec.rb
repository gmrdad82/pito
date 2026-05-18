require "rails_helper"

# `Composite::Layout::Netflix7` — 7 members: 1 big top + 3 mid row +
# 3 bottom row on the 300×400 canvas. Bands sized 0.5 / 0.25 / 0.25.
RSpec.describe Composite::Layout::Netflix7 do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'netflix7'" do
    expect(described_class.layout_name).to eq("netflix7")
  end

  it "exposes 7 cells: big top + two rows of thirds" do
    cells = described_class.cells
    third = 1.0 / 3.0
    expect(cells.size).to eq(7)
    # Big top — full width, top half
    expect(cells[0]).to eq({ x: 0.0, y: 0.0, w: 1.0, h: 0.5 })
    # Mid row (3 cells)
    expect(cells[1][:y]).to eq(0.5)
    expect(cells[1][:w]).to be_within(0.0001).of(third)
    expect(cells[3][:x]).to be_within(0.0001).of(2.0 * third)
    # Bot row (3 cells)
    expect(cells[4][:y]).to eq(0.75)
    expect(cells[6][:x]).to be_within(0.0001).of(2.0 * third)
  end

  it "covers the full unit square (∑w*h ≈ 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from 7 tiles" do
    out = described_class.compose(Array.new(7) { tile })
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError on the wrong tile count" do
    expect { described_class.compose(Array.new(6) { tile }) }.to raise_error(ArgumentError, /7 tiles/)
    expect { described_class.compose(Array.new(8) { tile }) }.to raise_error(ArgumentError)
  end
end
