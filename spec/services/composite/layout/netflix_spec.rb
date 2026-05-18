require "rails_helper"

# `Composite::Layout::Netflix` — 3 members: 1 big left + 2 stacked right
# on the 300×400 canvas.
RSpec.describe Composite::Layout::Netflix do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'netflix'" do
    expect(described_class.layout_name).to eq("netflix")
  end

  it "exposes 3 cells (left big + 2 right half-height)" do
    cells = described_class.cells
    expect(cells.size).to eq(3)
    expect(cells[0]).to eq({ x: 0.0, y: 0.0, w: 0.5, h: 1.0 })
    expect(cells[1]).to eq({ x: 0.5, y: 0.0, w: 0.5, h: 0.5 })
    expect(cells[2]).to eq({ x: 0.5, y: 0.5, w: 0.5, h: 0.5 })
  end

  it "covers the full unit square (∑w*h == 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from 3 tiles" do
    out = described_class.compose([ tile, tile, tile ])
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError on the wrong tile count" do
    expect { described_class.compose([ tile, tile ]) }.to raise_error(ArgumentError, /3 tiles/)
    expect { described_class.compose([ tile ] * 4) }.to raise_error(ArgumentError)
  end
end
