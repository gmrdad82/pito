require "rails_helper"

RSpec.describe Composite::TileCache do
  let(:cache) { described_class.new }
  let(:cover_image_id) { "co_test_abc" }
  let(:fixture_path) { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }
  let(:fixture_bytes) { File.binread(fixture_path) }

  before do
    # Wipe any prior tile cache entries so each example starts cold.
    tile_path = cache.tile_path(cover_image_id)
    File.delete(tile_path) if File.exist?(tile_path)
  end

  describe "#fetch" do
    it "downloads from the IGDB CDN on cache miss" do
      stub_request(:get, "https://images.igdb.com/igdb/image/upload/t_cover_big/#{cover_image_id}.jpg")
        .to_return(status: 200, body: fixture_bytes)

      img = cache.fetch(cover_image_id)
      expect(img).to be_a(Vips::Image)
      expect(img.width).to eq(227)
      expect(img.height).to eq(320)
    end

    it "writes the bytes to the cache after download" do
      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)
      cache.fetch(cover_image_id)

      expect(File.exist?(cache.tile_path(cover_image_id))).to be(true)
    end

    it "reads from the cache on hit (no second HTTP call)" do
      tile_path = cache.tile_path(cover_image_id)
      FileUtils.mkdir_p(tile_path.dirname)
      FileUtils.cp(fixture_path, tile_path)

      # Stub with a flaky response — if it's actually called the test
      # will see a webmock NetConnectNotAllowed on the second invocation.
      stub_request(:get, %r{images\.igdb\.com}).to_return(status: 500)
      cache.fetch(cover_image_id)

      expect(WebMock).not_to have_requested(:get, %r{images\.igdb\.com})
    end

    it "raises TileFetchError on non-200 IGDB CDN response" do
      stub_request(:get, %r{images\.igdb\.com}).to_return(status: 404)
      expect { cache.fetch(cover_image_id) }
        .to raise_error(Composite::TileFetchError, /404/)
    end

    it "raises ArgumentError on blank cover_image_id" do
      expect { cache.fetch("") }.to raise_error(ArgumentError)
      expect { cache.fetch(nil) }.to raise_error(ArgumentError)
    end
  end

  describe "#evict" do
    it "removes the tile from the cache" do
      tile_path = cache.tile_path(cover_image_id)
      FileUtils.mkdir_p(tile_path.dirname)
      FileUtils.cp(fixture_path, tile_path)

      cache.evict(cover_image_id)
      expect(File.exist?(tile_path)).to be(false)
    end

    it "no-ops when the tile is not present" do
      expect { cache.evict("missing-id-#{SecureRandom.hex(4)}") }.not_to raise_error
    end

    it "no-ops on blank input" do
      expect { cache.evict(nil) }.not_to raise_error
      expect { cache.evict("") }.not_to raise_error
    end
  end
end
