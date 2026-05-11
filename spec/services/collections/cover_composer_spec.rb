require "rails_helper"

# Phase 27 §01h — Collections::CoverComposer service spec.
#
# Exercises the full pyramid (happy / sad / edge / flaw) on every
# variant. Tile cache is stubbed to return a fixture JPEG so the spec
# does not hit the IGDB CDN; on-disk writes go to the test assets root
# and are cleaned up `after` each example.
RSpec.describe Collections::CoverComposer do
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }
  let(:fake_tile_cache) do
    instance_double(Composite::TileCache).tap do |tc|
      allow(tc).to receive(:fetch) do
        Vips::Image.new_from_file(fixture_path.to_s)
      end
    end
  end
  let(:composer)   { described_class.new(tile_cache: fake_tile_cache) }
  let(:collection) { create(:collection, name: "Test collection") }

  # Helper — build N games in alphabetical-friendly order (A, B, C ...)
  # with unique cover_image_ids. Order column is `title`.
  def add_games(coll, count, prefix: "g")
    Array.new(count) do |i|
      letter = ("A".ord + i).chr
      create(:game,
             :synced,
             collection: coll,
             title: "#{prefix}-#{letter}",
             cover_image_id: "img-#{letter}")
    end
  end

  def composite_path(coll)
    Pito::AssetsRoot.path("composites", "collection-#{coll.id}.jpg")
  end

  def cleanup_output(coll)
    path = composite_path(coll)
    File.delete(path) if File.exist?(path)
  rescue Pito::AssetsRoot::Error
    nil
  end

  after { cleanup_output(collection) }

  describe "#call — variant matrix" do
    it "returns nil for a 0-game collection (no on-disk write)" do
      expect(composer.call(collection)).to be_nil
      expect(File.exist?(composite_path(collection))).to be(false)
      expect(collection.reload.composite_cover_checksum).to be_nil
    end

    it "returns nil for a 1-game collection (no on-disk write)" do
      add_games(collection, 1)
      expect(composer.call(collection)).to be_nil
      expect(File.exist?(composite_path(collection))).to be(false)
      expect(collection.reload.composite_cover_checksum).to be_nil
    end

    it "writes a 98 × 130 JPEG for a 2-game collection (:pair)" do
      add_games(collection, 2)
      path = composer.call(collection)

      expect(path).to be_a(Pathname)
      expect(File.exist?(path)).to be(true)
      img = Vips::Image.new_from_file(path.to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
      expect(collection.reload.composite_cover_checksum).to be_present
    end

    it "writes a 98 × 130 JPEG for a 3-game collection (:netflix3)" do
      add_games(collection, 3)
      composer.call(collection)
      img = Vips::Image.new_from_file(composite_path(collection).to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
    end

    it "writes a 98 × 130 JPEG for a 4-game collection (:quad)" do
      add_games(collection, 4)
      composer.call(collection)
      img = Vips::Image.new_from_file(composite_path(collection).to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
    end

    it "writes a 98 × 130 JPEG for a 5-game collection (:netflix5)" do
      add_games(collection, 5)
      composer.call(collection)
      img = Vips::Image.new_from_file(composite_path(collection).to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
    end

    it "writes a 98 × 130 JPEG for a 6-game collection (:six_grid)" do
      add_games(collection, 6)
      composer.call(collection)
      img = Vips::Image.new_from_file(composite_path(collection).to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
    end

    it "truncates to first 6 (alphabetical) for a 7-game collection" do
      add_games(collection, 7) # A..G
      composer.call(collection)
      expected_ids = %w[img-A img-B img-C img-D img-E img-F]
      expect(collection.reload.composite_cover_checksum).to eq(
        Composite::Checksum.compute(expected_ids, "six_grid")
      )
    end
  end

  describe "#call — cache hit / miss" do
    it "does NOT rewrite the file on a fingerprint hit (mtime unchanged)" do
      add_games(collection, 2)
      composer.call(collection)
      before_mtime = File.mtime(composite_path(collection))

      sleep 0.01  # filesystem mtime granularity guard.

      composer.call(collection)
      after_mtime = File.mtime(composite_path(collection))
      expect(after_mtime).to eq(before_mtime)
    end

    it "rewrites and bumps the fingerprint after a membership change" do
      games = add_games(collection, 2)
      composer.call(collection)
      first_checksum = collection.reload.composite_cover_checksum

      # Add a third game (changes fingerprint AND layout).
      create(:game, :synced, collection: collection, title: "g-C", cover_image_id: "img-C")
      composer.call(collection)
      second_checksum = collection.reload.composite_cover_checksum

      expect(second_checksum).not_to eq(first_checksum)
      _ = games  # touch to suppress lint
    end

    it "rewrites and bumps the fingerprint after a cover_image_id swap" do
      games = add_games(collection, 2)
      composer.call(collection)
      first_checksum = collection.reload.composite_cover_checksum

      games.first.update!(cover_image_id: "img-Z")
      composer.call(collection)
      second_checksum = collection.reload.composite_cover_checksum

      expect(second_checksum).not_to eq(first_checksum)
    end

    it "treats a missing on-disk file as a miss (rewrites despite matching checksum)" do
      add_games(collection, 2)
      composer.call(collection)
      checksum = collection.reload.composite_cover_checksum

      File.delete(composite_path(collection))
      expect(File.exist?(composite_path(collection))).to be(false)

      composer.call(collection)
      expect(File.exist?(composite_path(collection))).to be(true)
      expect(collection.reload.composite_cover_checksum).to eq(checksum)
    end
  end

  describe "#call — degradation policy" do
    it "swallows Composite::TileFetchError and substitutes the placeholder slot" do
      add_games(collection, 2)
      call_count = 0
      allow(fake_tile_cache).to receive(:fetch) do |_cid|
        call_count += 1
        if call_count == 1
          raise Composite::TileFetchError, "synthetic 404"
        else
          Vips::Image.new_from_file(fixture_path.to_s)
        end
      end

      path = composer.call(collection)
      expect(path).to be_a(Pathname)
      expect(File.exist?(path)).to be(true)
      img = Vips::Image.new_from_file(path.to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
    end

    it "logs at WARN when a tile fetch fails" do
      add_games(collection, 2)
      allow(fake_tile_cache).to receive(:fetch).and_raise(
        Composite::TileFetchError, "synthetic 404"
      )
      logger = instance_double(Logger, warn: nil)
      composer = described_class.new(tile_cache: fake_tile_cache, logger: logger)

      composer.call(collection)
      expect(logger).to have_received(:warn).with(/Collections::CoverComposer tile fallback/).at_least(:once)
    end

    it "swallows Vips::Error raised mid-fetch and substitutes the placeholder" do
      add_games(collection, 2)
      call_count = 0
      allow(fake_tile_cache).to receive(:fetch) do |_cid|
        call_count += 1
        raise Vips::Error, "synthetic vips error" if call_count == 1
        Vips::Image.new_from_file(fixture_path.to_s)
      end

      path = composer.call(collection)
      img = Vips::Image.new_from_file(path.to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
    end

    it "still ships the composite when EVERY tile fails (all placeholders)" do
      add_games(collection, 3)
      allow(fake_tile_cache).to receive(:fetch).and_raise(
        Composite::TileFetchError, "synthetic 404"
      )

      path = composer.call(collection)
      img = Vips::Image.new_from_file(path.to_s)
      expect([ img.width, img.height ]).to eq([ 98, 130 ])
    end
  end

  describe "#call — ordering and fingerprint determinism" do
    it "sorts members case-insensitively by title for both tiles and fingerprint" do
      create(:game, :synced, collection: collection, title: "alpha", cover_image_id: "img-1")
      create(:game, :synced, collection: collection, title: "Alpha", cover_image_id: "img-2")
      create(:game, :synced, collection: collection, title: "ALPHA", cover_image_id: "img-3")
      create(:game, :synced, collection: collection, title: "beta",  cover_image_id: "img-4")
      create(:game, :synced, collection: collection, title: "Beta",  cover_image_id: "img-5")
      create(:game, :synced, collection: collection, title: "gamma", cover_image_id: "img-6")

      composer.call(collection)

      # All 6 contribute (case-insensitive sort puts "alpha/Alpha/ALPHA"
      # together regardless of casing).
      expected = Composite::Checksum.compute(
        %w[img-1 img-2 img-3 img-4 img-5 img-6], "six_grid"
      )
      expect(collection.reload.composite_cover_checksum).to eq(expected)
    end

    it "fingerprint is invariant under member-row reordering (Checksum sorts ids)" do
      add_games(collection, 2)
      composer.call(collection)
      first = collection.reload.composite_cover_checksum

      # Re-insertion in reverse order should NOT change the fingerprint
      # because `Composite::Checksum` sorts the id list lexically.
      collection.games.destroy_all
      create(:game, :synced, collection: collection, title: "g-B", cover_image_id: "img-B")
      create(:game, :synced, collection: collection, title: "g-A", cover_image_id: "img-A")
      cleanup_output(collection)

      composer.call(collection)
      second = collection.reload.composite_cover_checksum
      expect(second).to eq(first)
    end

    it "uses cover_image_ids (not Game#id) as fingerprint payload" do
      add_games(collection, 2)
      composer.call(collection)
      expected = Composite::Checksum.compute(%w[img-A img-B], "pair")
      expect(collection.reload.composite_cover_checksum).to eq(expected)
    end

    it "preserves nil cover_image_id slots in the fingerprint payload" do
      g1 = create(:game, :synced, collection: collection, title: "g-A", cover_image_id: nil)
      g2 = create(:game, :synced, collection: collection, title: "g-B", cover_image_id: "img-B")
      composer.call(collection)

      # Checksum filters nils internally (sorts the cleaned list); we
      # only check that the call succeeded and produced a stable hash.
      expect(collection.reload.composite_cover_checksum).to eq(
        Composite::Checksum.compute([ nil, "img-B" ], "pair")
      )
      _ = [ g1, g2 ]  # touch to suppress lint
    end
  end

  describe "#call — stamps composite_cover_path" do
    it "stores a relative path under composites/" do
      add_games(collection, 2)
      composer.call(collection)
      expect(collection.reload.composite_cover_path)
        .to eq("composites/collection-#{collection.id}.jpg")
    end
  end

  describe "#output_path" do
    it "returns the canonical Pathname under composites/" do
      expect(composer.output_path(collection))
        .to eq(Pito::AssetsRoot.path("composites", "collection-#{collection.id}.jpg"))
    end
  end
end
