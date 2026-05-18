require "rails_helper"

# Phase 27 follow-up (2026-05-17) — `Games::CoverArt::Normalizer` spec.
#
# Fetches `t_cover_big_2x` from the IGDB CDN, center-crops + resizes to
# the canonical 600×800 master, and writes it atomically to
# `<assets-root>/covers/games/<game_id>/master.jpg`. Idempotent against
# `igdb_synced_at` mtime; short-circuits when the master is fresh.
RSpec.describe Games::CoverArt::Normalizer do
  let(:fixture_path)  { Rails.root.join("spec/fixtures/files/cover_tile.jpg") }
  let(:fixture_bytes) { File.binread(fixture_path) }
  let(:tmp_root)      { Dir.mktmpdir("pito-assets-normalizer-spec") }

  around do |example|
    prev = ENV["PITO_ASSETS_PATH"]
    ENV["PITO_ASSETS_PATH"] = tmp_root
    example.run
  ensure
    ENV["PITO_ASSETS_PATH"] = prev
    FileUtils.remove_entry(tmp_root) if File.exist?(tmp_root)
  end

  def cdn_url_for(image_id)
    "https://images.igdb.com/igdb/image/upload/t_cover_big_2x/#{image_id}.jpg"
  end

  describe "#call — happy path" do
    let(:game) { create(:game, :synced, cover_image_id: "co_norm_abc") }

    it "fetches t_cover_big_2x from the IGDB CDN" do
      stub = stub_request(:get, cdn_url_for("co_norm_abc"))
               .to_return(status: 200, body: fixture_bytes)

      described_class.new(game: game).call

      expect(stub).to have_been_requested
    end

    it "writes the master to <assets-root>/covers/games/<id>/master.jpg" do
      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      result = described_class.new(game: game).call

      expected = Pito::AssetsRoot.path("covers", "games", game.id.to_s, "master.jpg")
      expect(result).to eq(expected.to_s)
      expect(File.exist?(expected)).to be(true)
    end

    it "normalizes the JPEG close to the canonical 600×800 (3:4) master" do
      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      result = described_class.new(game: game).call
      img = Vips::Image.new_from_file(result)
      # `Vips::Image#resize(scale)` rounds the dependent dimension; the
      # 227×320 fixture lands at 600×801 (off by one pixel) after the
      # crop-to-3:4 + scale-to-600-wide pipeline. Both sides should be
      # within 1px of the canonical target.
      expect(img.width).to be_within(1).of(described_class::MASTER_W)
      expect(img.height).to be_within(1).of(described_class::MASTER_H)
    end

    it "creates the per-game parent directory if it does not exist" do
      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      described_class.new(game: game).call

      parent = Pito::AssetsRoot.path("covers", "games", game.id.to_s)
      expect(File.directory?(parent)).to be(true)
    end

    it "leaves no `*.tmp.<pid>` sidecar after a successful write" do
      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      described_class.new(game: game).call

      parent = Pito::AssetsRoot.path("covers", "games", game.id.to_s)
      leftovers = Dir.children(parent).grep(/\.tmp\./)
      expect(leftovers).to be_empty
    end
  end

  describe "#call — no cover_image_id" do
    it "returns nil and writes nothing when cover_image_id is blank" do
      game = create(:game, cover_image_id: nil)
      result = described_class.new(game: game).call
      expect(result).to be_nil
      # No HTTP traffic should be attempted (would raise NetConnectNotAllowed otherwise).
    end
  end

  describe "#call — idempotency" do
    let(:game) { create(:game, :synced, cover_image_id: "co_norm_xyz") }

    it "short-circuits when the master file exists with mtime ≥ igdb_synced_at" do
      target = Pito::AssetsRoot.path("covers", "games", game.id.to_s, "master.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture_path, target)
      # Bump mtime to after igdb_synced_at so the freshness check wins.
      # `File.utime` needs `Time`, not `ActiveSupport::TimeWithZone`.
      future = (game.igdb_synced_at + 60).to_time
      File.utime(future, future, target)

      result = described_class.new(game: game).call

      expect(result).to eq(target.to_s)
      expect(WebMock).not_to have_requested(:get, %r{images\.igdb\.com})
    end

    it "re-normalizes when the master file is older than igdb_synced_at" do
      target = Pito::AssetsRoot.path("covers", "games", game.id.to_s, "master.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture_path, target)
      stale_time = (game.igdb_synced_at - 86_400).to_time
      File.utime(stale_time, stale_time, target)

      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      described_class.new(game: game).call

      expect(WebMock).to have_requested(:get, %r{images\.igdb\.com})
    end

    it "re-normalizes on every call when igdb_synced_at is nil (never synced)" do
      game_unsynced = create(:game, cover_image_id: "co_unsynced", igdb_synced_at: nil)
      target = Pito::AssetsRoot.path("covers", "games", game_unsynced.id.to_s, "master.jpg")
      FileUtils.mkdir_p(target.dirname)
      FileUtils.cp(fixture_path, target)

      stub_request(:get, %r{images\.igdb\.com})
        .to_return(status: 200, body: fixture_bytes)

      described_class.new(game: game_unsynced).call

      expect(WebMock).to have_requested(:get, %r{images\.igdb\.com})
    end
  end

  describe "#call — error paths" do
    let(:game) { create(:game, :synced, cover_image_id: "co_norm_err") }

    it "raises with the CDN status code on a 404" do
      stub_request(:get, %r{images\.igdb\.com}).to_return(status: 404)

      expect { described_class.new(game: game).call }
        .to raise_error(/404.*co_norm_err/)
    end

    it "raises with the CDN status code on a 500" do
      stub_request(:get, %r{images\.igdb\.com}).to_return(status: 500)

      expect { described_class.new(game: game).call }.to raise_error(/500/)
    end

    it "propagates Net::OpenTimeout when the CDN is hung" do
      stub_request(:get, %r{images\.igdb\.com}).to_timeout

      expect { described_class.new(game: game).call }.to raise_error(
        an_instance_of(Net::OpenTimeout).or(an_instance_of(Net::ReadTimeout))
      )
    end
  end

  describe "HTTP timeouts" do
    let(:game) { create(:game, :synced, cover_image_id: "co_norm_to") }

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

      described_class.new(game: game).call

      expect(captured).to be_a(Net::HTTP)
      expect(captured.open_timeout).to  eq(described_class::OPEN_TIMEOUT_SEC)
      expect(captured.read_timeout).to  eq(described_class::READ_TIMEOUT_SEC)
      expect(captured.write_timeout).to eq(described_class::WRITE_TIMEOUT_SEC)
    end

    it "uses SSL because the IGDB CDN URL is HTTPS" do
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

      described_class.new(game: game).call

      expect(captured.use_ssl?).to be(true)
    end
  end

  describe "constants" do
    it "targets a 600×800 master (3:4)" do
      expect(described_class::MASTER_W).to eq(600)
      expect(described_class::MASTER_H).to eq(800)
    end

    it "fetches the t_cover_big_2x IGDB token" do
      expect(described_class::SOURCE_SIZE).to eq("t_cover_big_2x")
    end

    it "encodes at JPEG quality 95 (upstream master — high fidelity)" do
      expect(described_class::JPEG_QUALITY).to eq(95)
    end
  end
end
