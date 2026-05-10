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

  # Phase 14 audit F2 — the IGDB CDN GET MUST set bounded HTTP timeouts
  # so a hung images.igdb.com edge cannot wedge a `BundleCoverBuild`
  # worker indefinitely. Mirrors the Phase 15 fix-forward pattern
  # landed in `Youtube::ServiceFactory` and `Igdb::Client` (F1).
  describe "HTTP timeouts (audit F2)" do
    it "sets open / read / write timeouts on the Net::HTTP instance" do
      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      captured = nil
      original_start = Net::HTTP.method(:start)
      allow(Net::HTTP).to receive(:start) do |host, port, opts = {}, &block|
        original_start.call(host, port, opts) do |http|
          captured = http
          block.call(http)
        end
      end

      cache.fetch(cover_image_id)

      expect(captured).to be_a(Net::HTTP)
      expect(captured.open_timeout).to  eq(Composite::TileCache::OPEN_TIMEOUT_SEC)
      expect(captured.read_timeout).to  eq(Composite::TileCache::READ_TIMEOUT_SEC)
      expect(captured.write_timeout).to eq(Composite::TileCache::WRITE_TIMEOUT_SEC)
    end

    it "uses SSL because the IGDB CDN base URL is HTTPS" do
      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      captured = nil
      original_start = Net::HTTP.method(:start)
      allow(Net::HTTP).to receive(:start) do |host, port, opts = {}, &block|
        original_start.call(host, port, opts) do |http|
          captured = http
          block.call(http)
        end
      end

      cache.fetch(cover_image_id)

      expect(captured.use_ssl?).to be(true)
    end

    it "surfaces a hung connection as Net::OpenTimeout to the caller" do
      # Sad-path proof: when the underlying connection raises a timeout
      # error, it bubbles up the stack instead of getting swallowed.
      stub_request(:get, %r{images\.igdb\.com}).to_timeout

      expect { cache.fetch(cover_image_id) }.to raise_error(
        an_instance_of(Net::OpenTimeout).or(an_instance_of(Net::ReadTimeout))
      )
    end
  end
end
