# Phase 14 §2 / Phase 27 follow-up (2026-05-17) — Composite cover builder.
#
# Orchestrator. Given a `Bundle`:
#   1. Loads ordered members + their `cover_image_id` values.
#   2. Picks the layout class via `LayoutChooser`.
#   3. Fetches each tile via `TileCache` (hit or download).
#   4. Composes the tiles into a 300×400 image via the layout.
#   5. Applies a libvips sharpen pass (sigma 1.0) to crisp the
#      downsampled tile edges before encoding.
#   6. Writes the JPEG to
#      `<PITO_ASSETS_PATH>/covers/bundles/<id>/composite.jpg`. All cover-art
#      assets — game masters and bundle composites — live under a single
#      `/covers/` namespace; the per-resource-type subdir
#      (`games/<id>/master.jpg`, `bundles/<id>/composite.jpg`) keeps the
#      namespace extensible.
#   7. Stamps `bundle.composite_cover_path` (relative, e.g.
#      `covers/bundles/<id>/composite.jpg`) and
#      `bundle.composite_cover_checksum` (SHA-256 over members + layout).
#
# Render canvas note (2026-05-17): canvas is 300×400, exactly 2× the
# 150×200 display size (retina 1:1, no browser-side downscale halos).
# Earlier iterations used 600×800; the 4× downscale to display was
# the dominant source of fuzziness. Halving the canvas also quarters
# the JPEG byte size at the same quality.
#
# Sharpen + quality note (2026-05-17 second pass): sigma raised from
# 0.5 to 1.0 for more pronounced edges — still conservative enough
# to avoid halos at the 300×400 canvas. JPEG quality raised from 85
# to 92 to preserve those sharpened edges through compression. The
# file size grows ~20-30% but the resulting tiles look noticeably
# crisper at retina display size.
#
# Idempotent — running `call` twice on an unchanged bundle produces
# the same checksum and writes the same bytes back.
#
# Members without `cover_image_id` are filtered out before composing.
# When the resulting list is empty, the cover is cleared (path +
# checksum set to nil) and no file is written; method returns `nil`.
#
# 2026-05-17 — the filename used to interpolate `bundle.bundle_type`
# (`series-<id>.jpg`, `collection-<id>.jpg`, etc.). The discriminator
# column is gone; every composite now writes to
# `covers/bundles/<id>/composite.jpg` (the legacy flat layout
# `composites/bundle-<id>.jpg` was retired on the same day in favor of
# the unified `/covers/<type>/<id>/...` layout).
class Bundle
  module Composite
    class Builder
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400
      JPEG_QUALITY  = 92
      SHARPEN_SIGMA = 1.0

      def initialize(tile_cache: TileCache.new)
        @tile_cache = tile_cache
      end

      def call(bundle)
        members = bundle.bundle_members.includes(:game).order(:position).to_a
        tile_games = members.map(&:game).select { |g| g.cover_image_id.present? }
        cover_image_ids = tile_games.map(&:cover_image_id)

        if cover_image_ids.empty?
          bundle.update!(composite_cover_path: nil,
                         composite_cover_checksum: nil)
          return nil
        end

        layout = Bundle::Composite::LayoutChooser.choose(cover_image_ids.size)
        # CountOverflow renders a solid color tile with no game images.
        # All other layouts need tile images fetched from TileCache.
        # Phase 27 follow-up (2026-05-17) — switched to `fetch_for_game`
        # so the local cover-art master
        # (`/covers/games/<id>/master.jpg`) is preferred over an IGDB
        # HTTPS round-trip when present.
        if layout == Bundle::Composite::Layout::CountOverflow
          tiles = []
        else
          tiles = tile_games.map { |g| @tile_cache.fetch_for_game(g) }
        end
        # Pass total bundle member count (not just those with cover images) so
        # CountOverflow displays the true game count for the bundle.
        composite = layout.compose(tiles, total_member_count: members.size)
        # Light edge sharpen — recovers crispness lost in the tile resize
        # without introducing visible halos. Applied once to the final
        # composite (not per-tile) so the cost is constant per build.
        composite = composite.sharpen(sigma: SHARPEN_SIGMA)

        path = output_path(bundle)
        FileUtils.mkdir_p(path.dirname)
        composite.jpegsave(path.to_s, Q: JPEG_QUALITY, strip: true)

        relative = path.relative_path_from(Pito::AssetsRoot.root).to_s
        checksum = Bundle::Composite::Checksum.compute(cover_image_ids, layout.layout_name)
        bundle.update!(composite_cover_path: relative,
                       composite_cover_checksum: checksum)
        path
      end

      def output_path(bundle)
        Pito::AssetsRoot.path("covers", "bundles", bundle.id.to_s, "composite.jpg")
      end
    end
  end
end
