# Phase 27 follow-up (2026-05-17) — Master cover-art normalizer.
#
# Fetches the largest official IGDB cover variant for a Game, normalizes
# it to a canonical 600×800 (3:4) JPEG via libvips, and writes the
# result to `<PITO_ASSETS_PATH>/covers/<game_id>/master.jpg`. The master
# file is the single source of truth for every downstream cover-art
# consumer (composite tile cells, /games tile, game show page hero,
# etc. — wired in by S5; this service does NOT touch consumers).
#
# The cover masters live on the `pito-assets` named volume (declared
# in `docker-compose.yml`, mounted at `PITO_ASSETS_PATH`) alongside the
# existing composites + footage thumbnails. On Hetzner the same volume
# migrates with the install, so masters persist across deploys without
# a separate backup story.
#
# Decisions captured during the user chat 2026-05-17:
#
#   - Master dimensions: 600 × 800 (3:4 aspect). The IGDB audit
#     confirmed all 13 current bundle games have native originals
#     ≥ 600 × 800, so this never up-scales.
#   - Source token: `t_cover_big_2x` (~528 × 748). The highest
#     official IGDB cover-image variant; safe for every current row
#     per the audit.
#   - Encoding: JPEG quality 95. Higher than the composite (Q92) and
#     tile (default) paths because the master is the upstream — every
#     downstream re-encode compounds loss.
#   - Output path: `<PITO_ASSETS_PATH>/covers/<game_id>/master.jpg`.
#     Per-game directory so future variants (`hero.jpg`, `tile.jpg`,
#     etc.) can coexist without a flat-namespace collision. Path
#     resolution flows through `Pito::AssetsRoot.path` so the same
#     containment / cleanpath guarantees that protect composites and
#     footage thumbnails also apply here.
#
# Idempotency: if the target file already exists AND its mtime is
# newer than `game.igdb_synced_at`, the call short-circuits and
# returns the path without re-fetching. A re-sync (`igdb_synced_at`
# bumped) re-normalizes because the IGDB cover bytes may have
# changed.
#
# Atomic write: the JPEG is streamed to a `*.tmp.<pid>` sibling and
# `File.rename`'d into place so a crash mid-write never leaves a
# half-written file that downstream consumers could read.
#
# Returns the absolute target path (`String`) when written or
# short-circuited. Returns `nil` when the Game has no `cover_image_id`
# (no IGDB cover to normalize) — callers treat that as the no-op case.
#
# NOT wired into `GameIgdbSync` (S3 owns that hook) and NOT exposed as
# a rake task (S4 owns that). Tests deferred per the iteration-mode
# dispatch contract — Wave F adds spec coverage.
require "fileutils"
require "net/http"
require "uri"

module Games
  module CoverArt
    class Normalizer
      MASTER_W = 600
      MASTER_H = 800
      JPEG_QUALITY = 95
      SOURCE_SIZE = "t_cover_big_2x"

      # Bounded HTTP timeouts so a hung IGDB CDN response cannot wedge
      # this synchronous service. Mirrors the `Composite::TileCache`
      # tuning landed in Phase 14 audit F2.
      OPEN_TIMEOUT_SEC  = 5
      READ_TIMEOUT_SEC  = 10
      WRITE_TIMEOUT_SEC = 5

      def initialize(game:)
        @game = game
      end

      def call
        return nil if @game.cover_image_id.blank?

        target = target_path
        return target.to_s if fresh?(target)

        FileUtils.mkdir_p(target.dirname)

        buffer = fetch_source_bytes
        img = normalize(buffer)
        write_jpeg_atomic(img, target)

        target.to_s
      end

      private

      def target_path
        Pito::AssetsRoot.path("covers", @game.id.to_s, "master.jpg")
      end

      # Idempotency check — the file is "fresh" when it exists and its
      # mtime is newer than the game's last IGDB sync. A re-sync bumps
      # `igdb_synced_at`, which forces a re-normalize on the next call
      # because the IGDB cover bytes may have changed. A game with a
      # nil `igdb_synced_at` (never synced) skips this branch entirely
      # — the file is regenerated on every call until the first sync
      # lands.
      def fresh?(target)
        return false unless target.exist?
        return false if @game.igdb_synced_at.blank?

        target.mtime >= @game.igdb_synced_at
      end

      def fetch_source_bytes
        url = "https://images.igdb.com/igdb/image/upload/#{SOURCE_SIZE}/#{@game.cover_image_id}.jpg"
        uri = URI(url)
        response = Net::HTTP.start(uri.host, uri.port, use_ssl: true) do |http|
          http.open_timeout  = OPEN_TIMEOUT_SEC
          http.read_timeout  = READ_TIMEOUT_SEC
          http.write_timeout = WRITE_TIMEOUT_SEC
          http.get(uri.request_uri)
        end
        unless response.is_a?(Net::HTTPSuccess)
          raise "IGDB CDN returned #{response.code} for #{@game.cover_image_id} (#{SOURCE_SIZE})"
        end
        response.body
      end

      # Center-crop to 3:4 aspect when the source ratio differs, then
      # resize to exactly MASTER_W × MASTER_H. The 0.001 tolerance
      # absorbs rounding noise — e.g. `t_cover_big_2x`'s native 528×748
      # is ~0.7059, the target 600×800 is 0.75; the difference is
      # always > 0.001 for off-aspect sources so the crop branch
      # always runs when needed.
      def normalize(buffer)
        img = Vips::Image.new_from_buffer(buffer, "")

        target_aspect = MASTER_W.to_f / MASTER_H
        source_aspect = img.width.to_f / img.height

        if (source_aspect - target_aspect).abs > 0.001
          if source_aspect > target_aspect
            # Source is wider than 3:4 — center-crop width.
            new_w = (img.height * target_aspect).round
            x_offset = ((img.width - new_w) / 2).round
            img = img.crop(x_offset, 0, new_w, img.height)
          else
            # Source is taller than 3:4 — center-crop height.
            new_h = (img.width / target_aspect).round
            y_offset = ((img.height - new_h) / 2).round
            img = img.crop(0, y_offset, img.width, new_h)
          end
        end

        scale = MASTER_W.to_f / img.width
        img.resize(scale)
      end

      # Stream to a sibling temp file then atomically rename into the
      # target path so an interrupted write never leaves a half-written
      # JPEG that a downstream reader could pick up. `strip: true`
      # drops the EXIF block (IGDB delivers it; we don't need it) and
      # `optimize_coding: true` runs the second Huffman pass that
      # shaves a few percent off the final byte size at no quality
      # cost.
      def write_jpeg_atomic(img, target)
        tmp = target.sub_ext(".jpg.tmp.#{Process.pid}")
        img.jpegsave(tmp.to_s, Q: JPEG_QUALITY, strip: true, optimize_coding: true)
        File.rename(tmp.to_s, target.to_s)
      end
    end
  end
end
