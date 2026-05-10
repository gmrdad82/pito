require "rails_helper"

RSpec.describe Composite::Layout::Pair do
  let(:tile) { Vips::Image.new_from_file(Rails.root.join("spec/fixtures/files/cover_tile.jpg").to_s) }

  it "exposes layout_name 'pair'" do
    expect(described_class.layout_name).to eq("pair")
  end

  it "produces a 600×800 image from 2 tiles" do
    out = described_class.compose([ tile, tile ])
    expect(out.width).to eq(600)
    expect(out.height).to eq(800)
  end

  it "raises ArgumentError when given the wrong tile count" do
    expect { described_class.compose([ tile ]) }.to raise_error(ArgumentError)
    expect { described_class.compose([ tile, tile, tile ]) }.to raise_error(ArgumentError)
  end
end
