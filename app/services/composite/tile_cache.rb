# Phase 14 §2 — IGDB cover tile cache.
#
# Downloads the `t_cover_big` (227×320) variant of an IGDB cover image
# once per `cover_image_id` and caches the bytes under
# `<PITO_ASSETS_PATH>/composites/_tiles/<cover_image_id>.jpg`. Cache
# hits read from disk; misses fetch from `images.igdb.com` and write
# the bytes back. `evict` removes a single tile (called from
# `BundleCoverInvalidate` when a Game's `cover_image_id` changes).
#
# Non-200 IGDB responses raise `Composite::TileFetchError`; the
# `BundleCoverBuild` job re-raises so Sidekiq retries with backoff.
require "net/http"

module Composite
  class TileCache
    TILE_SIZE = "t_cover_big" # 227×320 per IGDB CDN
    BASE_URL  = "https://images.igdb.com/igdb/image/upload".freeze

    def fetch(cover_image_id)
      raise ArgumentError, "cover_image_id required" if cover_image_id.blank?

      path = tile_path(cover_image_id)
      return Vips::Image.new_from_file(path.to_s) if path.exist?

      FileUtils.mkdir_p(path.dirname)
      bytes = download(cover_image_id)
      File.binwrite(path, bytes)
      Vips::Image.new_from_file(path.to_s)
    end

    def evict(cover_image_id)
      return if cover_image_id.blank?
      path = tile_path(cover_image_id)
      File.delete(path) if path.exist?
    rescue Errno::ENOENT
      nil
    end

    def tile_path(cover_image_id)
      Pito::AssetsRoot.path("composites", "_tiles", "#{cover_image_id}.jpg")
    end

    private

    def download(cover_image_id)
      uri = URI("#{BASE_URL}/#{TILE_SIZE}/#{cover_image_id}.jpg")
      response = Net::HTTP.get_response(uri)
      unless response.is_a?(Net::HTTPSuccess)
        raise TileFetchError,
              "IGDB CDN returned #{response.code} for #{cover_image_id}"
      end
      response.body
    end
  end
end
