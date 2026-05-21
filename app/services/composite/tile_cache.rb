# Phase 14 §2 — IGDB cover tile cache.
#
# Downloads the `t_cover_big` (227×320) variant of an IGDB cover image
# once per `cover_image_id` and caches the bytes under
# `<PITO_ASSETS_PATH>/covers/_tiles/<cover_image_id>.jpg`. Cache
# hits read from disk; misses fetch from `images.igdb.com` and write
# the bytes back. `evict` removes a single tile (called from
# `BundleCoverInvalidate` when a Game's `cover_image_id` changes).
#
# The `_tiles/` subdir lives alongside `games/` and `bundles/` under the
# unified `/covers/` namespace introduced 2026-05-17 — the underscore
# prefix marks it as an internal cache (never linked from a public URL).
#
# Non-200 IGDB responses raise `Composite::TileFetchError`; the
# `BundleCoverBuild` job re-raises so Sidekiq retries with backoff.
#
# Phase 27 follow-up (2026-05-17) — `fetch_for_game(game)` prefers the
# normalized local master
# (`<PITO_ASSETS_PATH>/covers/games/<id>/master.jpg`) written by
# `Game::CoverArt::Normalizer` over a CDN download. Local FS read is
# dramatically faster than an HTTPS round-trip and avoids burning the
# `covers/_tiles/<cover_image_id>.jpg` cache slot when the master
# already covers the same need. Falls back to the legacy
# `fetch(cover_image_id)` path when the master is missing.
require "net/http"

module Composite
  class TileCache
    TILE_SIZE = "t_cover_big" # 227×320 per IGDB CDN
    BASE_URL  = "https://images.igdb.com/igdb/image/upload".freeze

    # Phase 14 audit F2 — bounded HTTP timeouts so a hung IGDB CDN
    # response cannot wedge a `BundleCoverBuild` worker indefinitely.
    # Mirrors `Igdb::Client`'s F1 timeouts and the webhook-style
    # 5 / 10 / 5 tuning landed elsewhere.
    OPEN_TIMEOUT_SEC  = 5
    READ_TIMEOUT_SEC  = 10
    WRITE_TIMEOUT_SEC = 5

    # Phase 27 follow-up (2026-05-17) — Game-aware fetch. Prefers the
    # normalized local master when present (zero HTTP, zero tile-cache
    # write); falls back to the legacy IGDB-by-cover-image-id path
    # when the master is missing for this game (not yet normalized).
    def fetch_for_game(game)
      raise ArgumentError, "game required" if game.nil?

      master = game.cover_master_path
      return Vips::Image.new_from_file(master) if master

      fetch(game.cover_image_id)
    end

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
      Pito::AssetsRoot.path("covers", "_tiles", "#{cover_image_id}.jpg")
    end

    private

    def download(cover_image_id)
      uri = URI("#{BASE_URL}/#{TILE_SIZE}/#{cover_image_id}.jpg")
      # Phase 14 audit F2 — explicit `Net::HTTP.start` block so we can
      # set bounded open / read / write timeouts. `Net::HTTP.get_response`
      # defaults to 60s open + 60s read, which is long enough to wedge
      # a `BundleCoverBuild` worker on a hung CDN edge.
      response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
        http.open_timeout  = OPEN_TIMEOUT_SEC
        http.read_timeout  = READ_TIMEOUT_SEC
        http.write_timeout = WRITE_TIMEOUT_SEC
        http.get(uri.request_uri)
      end
      unless response.is_a?(Net::HTTPSuccess)
        raise TileFetchError,
              "IGDB CDN returned #{response.code} for #{cover_image_id}"
      end
      response.body
    end
  end
end
