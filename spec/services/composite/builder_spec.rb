require "rails_helper"

# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Composite::Builder
# spec. After the 2026-05-17 simplification the composer:
#   - writes to `composites/bundle-<id>.jpg` (no bundle_type prefix);
#   - no longer touches `last_error` (the column is gone).
RSpec.describe Composite::Builder do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }
  let(:fake_tile_cache) do
    instance_double(Composite::TileCache).tap do |tc|
      allow(tc).to receive(:fetch) do
        Vips::Image.new_from_file(fixture_path.to_s)
      end
    end
  end
  let(:builder) { described_class.new(tile_cache: fake_tile_cache) }
  let(:bundle)  { create(:bundle) }

  def add_member(b, cover_image_id)
    g = create(:game, :synced, cover_image_id: cover_image_id)
    b.bundle_members.create!(game: g)
    g
  end

  def cleanup_output(b)
    [ b.composite_cover_path, "composites/bundle-#{b.id}.jpg" ].compact.each do |rel|
      next if rel.nil? || rel.empty?
      abs =
        begin
          Pito::AssetsRoot.path(*rel.split("/"))
        rescue Pito::AssetsRoot::Error
          nil
        end
      File.delete(abs) if abs && File.exist?(abs)
    end
  end

  after { cleanup_output(bundle) }

  it "writes a 600×800 JPEG for a 1-member bundle" do
    add_member(bundle, "img-1")
    builder.call(bundle.reload)

    expected = Pito::AssetsRoot.path("composites", "bundle-#{bundle.id}.jpg")
    expect(File.exist?(expected)).to be(true)
    img = Vips::Image.new_from_file(expected.to_s)
    expect(img.width).to eq(600)
    expect(img.height).to eq(800)
  end

  it "writes a 600×800 JPEG for a 2-member bundle" do
    2.times { |i| add_member(bundle, "img-#{i}") }
    builder.call(bundle.reload)
    img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
    expect(img.width).to eq(600)
    expect(img.height).to eq(800)
  end

  it "writes a 600×800 JPEG for a 3-member bundle (Netflix)" do
    3.times { |i| add_member(bundle, "img-#{i}") }
    builder.call(bundle.reload)
    img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
    expect(img.width).to eq(600)
    expect(img.height).to eq(800)
  end

  it "writes a 600×800 JPEG for a 4-member bundle (Quad)" do
    4.times { |i| add_member(bundle, "img-#{i}") }
    builder.call(bundle.reload)
    img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
    expect(img.width).to eq(600)
    expect(img.height).to eq(800)
  end

  it "uses NineGrid for 9 members" do
    9.times { |i| add_member(bundle, "img-#{i}") }
    builder.call(bundle.reload)
    expect(bundle.reload.composite_cover_checksum).to be_present
    expected = Composite::Checksum.compute(
      (0..8).map { |i| "img-#{i}" }, "nine_grid"
    )
    expect(bundle.composite_cover_checksum).to eq(expected)
  end

  it "uses NineGridWithOverflow for 10 members" do
    10.times { |i| add_member(bundle, "img-#{i}") }
    builder.call(bundle.reload)
    expected = Composite::Checksum.compute(
      (0..9).map { |i| "img-#{i}" }, "nine_grid_with_overflow"
    )
    expect(bundle.reload.composite_cover_checksum).to eq(expected)
  end

  it "clears path + checksum and writes no file when no members have cover_image_id" do
    g = create(:game, cover_image_id: nil) # no cover
    bundle.bundle_members.create!(game: g)

    expected_path = Pito::AssetsRoot.path("composites", "bundle-#{bundle.id}.jpg")
    File.delete(expected_path) if File.exist?(expected_path)

    result = builder.call(bundle.reload)
    expect(result).to be_nil
    expect(bundle.reload.composite_cover_path).to be_nil
    expect(bundle.composite_cover_checksum).to be_nil
    expect(File.exist?(expected_path)).to be(false)
  end

  it "filters out members with nil cover_image_id and builds with the rest" do
    add_member(bundle, "img-x")
    g_no_cover = create(:game, cover_image_id: nil)
    bundle.bundle_members.create!(game: g_no_cover)

    builder.call(bundle.reload)
    expect(bundle.reload.composite_cover_checksum).to eq(
      Composite::Checksum.compute([ "img-x" ], "single")
    )
  end

  it "writes the JPEG at the canonical `bundle-<id>.jpg` filename" do
    add_member(bundle, "img-1")
    builder.call(bundle.reload)
    expect(bundle.reload.composite_cover_path)
      .to eq("composites/bundle-#{bundle.id}.jpg")
  end

  it "writes under Pito::AssetsRoot (no tenant prefix)" do
    add_member(bundle, "img-1")
    builder.call(bundle.reload)
    expect(bundle.reload.composite_cover_path).not_to include("tenant-")
    expect(bundle.composite_cover_path).to start_with("composites/")
  end

  it "stamps composite_cover_checksum to match Checksum.compute" do
    add_member(bundle, "img-A")
    add_member(bundle, "img-B")
    builder.call(bundle.reload)
    expect(bundle.reload.composite_cover_checksum).to eq(
      Composite::Checksum.compute(%w[img-A img-B], "pair")
    )
  end

  it "is idempotent — second call leaves checksum unchanged" do
    add_member(bundle, "img-A")
    add_member(bundle, "img-B")
    builder.call(bundle.reload)
    cks1 = bundle.reload.composite_cover_checksum
    builder.call(bundle.reload)
    cks2 = bundle.reload.composite_cover_checksum
    expect(cks1).to eq(cks2)
  end
end
