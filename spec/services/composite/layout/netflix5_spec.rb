require "rails_helper"

# `Composite::Layout::Netflix5` — 5 members: 1 big left + 2×2 grid right
# on the 300×400 canvas.
RSpec.describe Composite::Layout::Netflix5 do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'netflix5'" do
    expect(described_class.layout_name).to eq("netflix5")
  end

  it "exposes 5 cells (left big + 2×2 right quarter cells)" do
    cells = described_class.cells
    expect(cells.size).to eq(5)
    expect(cells[0]).to eq({ x: 0.0,  y: 0.0, w: 0.5,  h: 1.0 })
    expect(cells[1]).to eq({ x: 0.5,  y: 0.0, w: 0.25, h: 0.5 })
    expect(cells[2]).to eq({ x: 0.75, y: 0.0, w: 0.25, h: 0.5 })
    expect(cells[3]).to eq({ x: 0.5,  y: 0.5, w: 0.25, h: 0.5 })
    expect(cells[4]).to eq({ x: 0.75, y: 0.5, w: 0.25, h: 0.5 })
  end

  it "covers the full unit square (∑w*h == 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from 5 tiles" do
    out = described_class.compose(Array.new(5) { tile })
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError on the wrong tile count" do
    expect { described_class.compose(Array.new(4) { tile }) }.to raise_error(ArgumentError, /5 tiles/)
    expect { described_class.compose(Array.new(6) { tile }) }.to raise_error(ArgumentError)
  end
end
