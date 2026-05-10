require "rails_helper"

RSpec.describe Composite::Layout::Netflix do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'netflix'" do
    expect(described_class.layout_name).to eq("netflix")
  end

  it "produces a 600×800 image from 3 tiles" do
    out = described_class.compose([ tile, tile, tile ])
    expect(out.width).to eq(600)
    expect(out.height).to eq(800)
  end

  it "raises ArgumentError on the wrong tile count" do
    expect { described_class.compose([ tile, tile ]) }.to raise_error(ArgumentError)
  end
end
