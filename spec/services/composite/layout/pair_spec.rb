require "rails_helper"

# `Composite::Layout::Pair` — 2 members; side-by-side, each half-width
# full-height on the 300×400 canvas.
RSpec.describe Composite::Layout::Pair do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'pair'" do
    expect(described_class.layout_name).to eq("pair")
  end

  it "exposes 2 equal-half cells (full height)" do
    cells = described_class.cells
    expect(cells.size).to eq(2)
    expect(cells[0]).to eq({ x: 0.0, y: 0.0, w: 0.5, h: 1.0 })
    expect(cells[1]).to eq({ x: 0.5, y: 0.0, w: 0.5, h: 1.0 })
  end

  it "covers the full unit square (∑w*h == 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from 2 tiles" do
    out = described_class.compose([ tile, tile ])
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError when given the wrong tile count" do
    expect { described_class.compose([ tile ]) }.to raise_error(ArgumentError, /2 tiles/)
    expect { described_class.compose([ tile, tile, tile ]) }.to raise_error(ArgumentError)
  end
end
