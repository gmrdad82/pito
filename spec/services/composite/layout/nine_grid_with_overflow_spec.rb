require "rails_helper"

RSpec.describe Composite::Layout::NineGridWithOverflow do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'nine_grid_with_overflow'" do
    expect(described_class.layout_name).to eq("nine_grid_with_overflow")
  end

  it "produces a 600×800 image from 9 tiles + total_member_count 10" do
    out = described_class.compose(Array.new(9) { tile }, total_member_count: 10)
    expect(out.width).to eq(600)
    expect(out.height).to eq(800)
  end

  it "produces a 600×800 image from 9 tiles + total_member_count 100" do
    out = described_class.compose(Array.new(9) { tile }, total_member_count: 100)
    expect(out.width).to eq(600)
    expect(out.height).to eq(800)
  end

  it "raises ArgumentError when not exactly 9 tiles" do
    expect { described_class.compose(Array.new(8) { tile }, total_member_count: 10) }
      .to raise_error(ArgumentError)
  end
end
