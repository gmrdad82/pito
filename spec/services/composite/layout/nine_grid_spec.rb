require "rails_helper"

RSpec.describe Composite::Layout::NineGrid do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'nine_grid'" do
    expect(described_class.layout_name).to eq("nine_grid")
  end

  it "produces a 600×800 image from 5 tiles (4 blanks)" do
    out = described_class.compose(Array.new(5) { tile })
    expect(out.width).to eq(600)
    expect(out.height).to eq(800)
  end

  it "produces a 600×800 image from 9 tiles" do
    out = described_class.compose(Array.new(9) { tile })
    expect(out.width).to eq(600)
    expect(out.height).to eq(800)
  end

  it "raises ArgumentError on tile count outside 5..9" do
    expect { described_class.compose(Array.new(4) { tile }) }.to raise_error(ArgumentError)
    expect { described_class.compose(Array.new(10) { tile }) }.to raise_error(ArgumentError)
  end
end
