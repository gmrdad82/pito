# Phase 14 §2 — Composite cover builder.
#
# Orchestrator. Given a `Bundle`:
#   1. Loads ordered members + their `cover_image_id` values.
#   2. Picks the layout class via `LayoutChooser`.
#   3. Fetches each tile via `TileCache` (hit or download).
#   4. Composes the tiles into a 600×800 image via the layout.
#   5. Writes the JPEG to
#      `<PITO_ASSETS_PATH>/composites/<bundle_type>-<bundle_id>.jpg`.
#   6. Stamps `bundle.composite_cover_path` (relative) and
#      `bundle.composite_cover_checksum` (SHA-256 over members + layout).
#
# Idempotent — running `call` twice on an unchanged bundle produces
# the same checksum and writes the same bytes back.
#
# Members without `cover_image_id` are filtered out before composing.
# When the resulting list is empty, the cover is cleared (path +
# checksum set to nil) and no file is written; method returns `nil`.
module Composite
  class Builder
    OUTPUT_WIDTH  = 600
    OUTPUT_HEIGHT = 800
    JPEG_QUALITY  = 80

    def initialize(tile_cache: TileCache.new)
      @tile_cache = tile_cache
    end

    def call(bundle)
      members = bundle.bundle_members.includes(:game).order(:position).to_a
      cover_image_ids = members.map { |bm| bm.game.cover_image_id }.compact

      if cover_image_ids.empty?
        bundle.update!(composite_cover_path: nil,
                       composite_cover_checksum: nil)
        return nil
      end

      layout = Composite::LayoutChooser.choose(cover_image_ids.size)
      tiles  = cover_image_ids.map { |cid| @tile_cache.fetch(cid) }
      composite = layout.compose(tiles, total_member_count: members.size)

      path = output_path(bundle)
      FileUtils.mkdir_p(path.dirname)
      composite.jpegsave(path.to_s, Q: JPEG_QUALITY, strip: true)

      relative = path.relative_path_from(Pito::AssetsRoot.root).to_s
      checksum = Composite::Checksum.compute(cover_image_ids, layout.layout_name)
      bundle.update!(composite_cover_path: relative,
                     composite_cover_checksum: checksum,
                     last_error: nil)
      path
    end

    def output_path(bundle)
      Pito::AssetsRoot.path("composites",
                            "#{bundle.bundle_type}-#{bundle.id}.jpg")
    end
  end
end
