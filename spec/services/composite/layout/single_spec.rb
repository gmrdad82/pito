require "rails_helper"

# `Composite::Layout::Single` — 1 member; resize to fill the full 300×400 canvas.
RSpec.describe Composite::Layout::Single do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'single'" do
    expect(described_class.layout_name).to eq("single")
  end

  it "exposes 1 cell that fills the entire unit square" do
    cells = described_class.cells
    expect(cells.size).to eq(1)
    expect(cells.first).to eq({ x: 0.0, y: 0.0, w: 1.0, h: 1.0 })
  end

  it "covers the full unit square (∑w*h == 1.0)" do
    coverage = described_class.cells.sum { |c| c[:w] * c[:h] }
    expect(coverage).to be_within(0.0001).of(1.0)
  end

  it "produces a 300×400 image from a single tile" do
    out = described_class.compose([ tile ])
    expect(out).to be_a(Vips::Image)
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "raises ArgumentError when given the wrong tile count" do
    expect { described_class.compose([ tile, tile ]) }.to raise_error(ArgumentError, /1 tile/)
    expect { described_class.compose([]) }.to raise_error(ArgumentError)
  end
end
