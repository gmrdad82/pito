require "rails_helper"

# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — `Composite::Builder` spec.
#
# Post-simplification builder:
#   - canvas is 300×400 (halved 2026-05-17 from 600×800);
#   - writes to `<assets-root>/covers/bundles/<id>/composite.jpg`;
#   - reads tiles via `TileCache#fetch_for_game(game)` (prefers the local
#     `covers/games/<id>/master.jpg`, falls back to IGDB CDN);
#   - stamps `bundle.composite_cover_path` (relative) +
#     `bundle.composite_cover_checksum`;
#   - is idempotent (same inputs → same checksum + same bytes).
RSpec.describe Composite::Builder do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }
  let(:fake_tile_cache) do
    instance_double(Composite::TileCache).tap do |tc|
      allow(tc).to receive(:fetch_for_game) do
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
    [ b.composite_cover_path, "covers/bundles/#{b.id}/composite.jpg" ].compact.each do |rel|
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

  describe "canvas size + path for each layout" do
    it "writes a 300×400 JPEG for a 1-member bundle (Single)" do
      add_member(bundle, "img-1")
      builder.call(bundle.reload)

      expected = Pito::AssetsRoot.path("covers", "bundles", bundle.id.to_s, "composite.jpg")
      expect(File.exist?(expected)).to be(true)
      img = Vips::Image.new_from_file(expected.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end

    it "writes a 300×400 JPEG for a 2-member bundle (Pair)" do
      2.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end

    it "writes a 300×400 JPEG for a 3-member bundle (Netflix)" do
      3.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end

    it "writes a 300×400 JPEG for a 4-member bundle (Quad)" do
      4.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end

    it "writes a 300×400 JPEG for a 5-member bundle (Netflix5)" do
      5.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end

    it "writes a 300×400 JPEG for a 6-member bundle (SixGrid)" do
      6.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end

    it "writes a 300×400 JPEG for a 7-member bundle (Netflix7)" do
      7.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end

    it "writes a 300×400 JPEG for an 8-member bundle (EightGrid)" do
      8.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      img = Vips::Image.new_from_file(bundle.reload.composite_cover_absolute_path.to_s)
      expect(img.width).to eq(300)
      expect(img.height).to eq(400)
    end
  end

  describe "checksum stamping per layout" do
    it "stamps `single` for a 1-member bundle" do
      add_member(bundle, "img-A")
      builder.call(bundle.reload)
      expect(bundle.reload.composite_cover_checksum).to eq(
        Composite::Checksum.compute([ "img-A" ], "single")
      )
    end

    it "stamps `pair` for a 2-member bundle" do
      add_member(bundle, "img-A")
      add_member(bundle, "img-B")
      builder.call(bundle.reload)
      expect(bundle.reload.composite_cover_checksum).to eq(
        Composite::Checksum.compute(%w[img-A img-B], "pair")
      )
    end

    it "stamps `netflix` for a 3-member bundle" do
      3.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      expected = Composite::Checksum.compute(
        (0..2).map { |i| "img-#{i}" }, "netflix"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end

    it "stamps `quad` for a 4-member bundle" do
      4.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      expected = Composite::Checksum.compute(
        (0..3).map { |i| "img-#{i}" }, "quad"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end

    it "stamps `netflix5` for 5 members" do
      5.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      expected = Composite::Checksum.compute(
        (0..4).map { |i| "img-#{i}" }, "netflix5"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end

    it "stamps `six_grid` for 6 members" do
      6.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      expected = Composite::Checksum.compute(
        (0..5).map { |i| "img-#{i}" }, "six_grid"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end

    it "stamps `netflix7` for 7 members" do
      7.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      expected = Composite::Checksum.compute(
        (0..6).map { |i| "img-#{i}" }, "netflix7"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end

    it "stamps `eight_grid` for 8 members" do
      8.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      expected = Composite::Checksum.compute(
        (0..7).map { |i| "img-#{i}" }, "eight_grid"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end

    it "stamps `nine_grid` for 9 members" do
      9.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      expected = Composite::Checksum.compute(
        (0..8).map { |i| "img-#{i}" }, "nine_grid"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end

    it "stamps `nine_grid_with_overflow` for 10 members" do
      10.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      # Only first 9 cover_image_ids contribute to the checksum (the
      # overflow caption is HTML-overlay, not baked into the JPEG, and
      # the builder slices the tile list to 9 before composing).
      expected = Composite::Checksum.compute(
        (0..9).map { |i| "img-#{i}" }, "nine_grid_with_overflow"
      )
      expect(bundle.reload.composite_cover_checksum).to eq(expected)
    end
  end

  describe "members without cover_image_id" do
    it "clears path + checksum and writes no file when no members have cover_image_id" do
      g = create(:game, cover_image_id: nil)
      bundle.bundle_members.create!(game: g)

      expected_path = Pito::AssetsRoot.path("covers", "bundles", bundle.id.to_s, "composite.jpg")
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
  end

  describe "output path conventions" do
    it "writes the JPEG at the canonical `covers/bundles/<id>/composite.jpg` path" do
      add_member(bundle, "img-1")
      builder.call(bundle.reload)
      expect(bundle.reload.composite_cover_path)
        .to eq("covers/bundles/#{bundle.id}/composite.jpg")
    end

    it "writes under the unified /covers/ namespace, no tenant or legacy prefix" do
      add_member(bundle, "img-1")
      builder.call(bundle.reload)
      path = bundle.reload.composite_cover_path
      expect(path).not_to include("tenant-")
      expect(path).not_to start_with("composites/")
      expect(path).to start_with("covers/bundles/")
    end

    it "returns the absolute Pathname of the written JPEG" do
      add_member(bundle, "img-1")
      result = builder.call(bundle.reload)
      expect(result).to be_a(Pathname)
      expect(result.to_s).to end_with("covers/bundles/#{bundle.id}/composite.jpg")
    end
  end

  describe "idempotency" do
    it "second call leaves checksum unchanged for the same membership set" do
      add_member(bundle, "img-A")
      add_member(bundle, "img-B")
      builder.call(bundle.reload)
      cks1 = bundle.reload.composite_cover_checksum
      builder.call(bundle.reload)
      cks2 = bundle.reload.composite_cover_checksum
      expect(cks1).to eq(cks2)
    end
  end

  describe "tile fetch routing" do
    it "fetches each contributing tile via TileCache#fetch_for_game (game-aware)" do
      g1 = add_member(bundle, "img-1")
      g2 = add_member(bundle, "img-2")
      builder.call(bundle.reload)

      expect(fake_tile_cache).to have_received(:fetch_for_game).with(g1)
      expect(fake_tile_cache).to have_received(:fetch_for_game).with(g2)
    end

    it "slices the tile list to the first 9 contributing members on overflow layout" do
      10.times { |i| add_member(bundle, "img-#{i}") }
      builder.call(bundle.reload)
      # `fetch_for_game` only ever called for the first 9 members in
      # `position` order — the 10th is overflow caption only.
      expect(fake_tile_cache).to have_received(:fetch_for_game).exactly(9).times
    end
  end

  describe "#output_path" do
    it "returns the absolute target Pathname under Pito::AssetsRoot" do
      result = builder.output_path(bundle)
      expect(result).to be_a(Pathname)
      expect(result.to_s).to end_with("covers/bundles/#{bundle.id}/composite.jpg")
      expect(result).to be_absolute
    end
  end
end
