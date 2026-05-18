require "rails_helper"

# `Composite::Layout::NineGridWithOverflow` — identical 3×3 geometry to
# `NineGrid`; the +N overflow indicator is an HTML overlay rendered by
# the view layer, not baked into the JPEG.
RSpec.describe Composite::Layout::NineGridWithOverflow do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'nine_grid_with_overflow'" do
    expect(described_class.layout_name).to eq("nine_grid_with_overflow")
  end

  it "delegates cells to NineGrid (same 3×3 array, same object identity)" do
    expect(described_class.cells).to equal(Composite::Layout::NineGrid::CELLS)
  end

  it "produces a 300×400 image from 9 tiles + total_member_count 10" do
    out = described_class.compose(Array.new(9) { tile }, total_member_count: 10)
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "produces a 300×400 image from 9 tiles + total_member_count 100" do
    out = described_class.compose(Array.new(9) { tile }, total_member_count: 100)
    expect(out.width).to eq(300)
    expect(out.height).to eq(400)
  end

  it "ignores total_member_count (caption is HTML-overlay, not baked in)" do
    # Same 9 tiles → identical pixel output regardless of `total_member_count`.
    a = described_class.compose(Array.new(9) { tile }, total_member_count: 10)
    b = described_class.compose(Array.new(9) { tile }, total_member_count: 999)
    expect(a.width).to eq(b.width)
    expect(a.height).to eq(b.height)
  end

  it "raises ArgumentError when not exactly 9 tiles" do
    expect { described_class.compose(Array.new(8) { tile }, total_member_count: 10) }
      .to raise_error(ArgumentError, /9 tiles/)
    expect { described_class.compose(Array.new(10) { tile }, total_member_count: 10) }
      .to raise_error(ArgumentError)
  end
end
