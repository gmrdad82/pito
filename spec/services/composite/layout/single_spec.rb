require "rails_helper"

RSpec.describe Composite::Layout::Single do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'single'" do
    expect(described_class.layout_name).to eq("single")
  end

  it "produces a 600×800 image from a single tile" do
    out = described_class.compose([ tile ])
    expect(out).to be_a(Vips::Image)
    expect(out.width).to eq(600)
    expect(out.height).to eq(800)
  end

  it "raises ArgumentError on the wrong tile count" do
    expect { described_class.compose([ tile, tile ]) }.to raise_error(ArgumentError)
  end
end
