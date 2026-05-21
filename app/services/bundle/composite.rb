# Phase 14 §2 — Bundle::Composite cover module namespace.
#
# Houses the bundle composite-cover builder pipeline:
#   - `Bundle::Composite::Builder`      — orchestrates the build
#   - `Bundle::Composite::TileCache`    — IGDB CDN tile cache (download + evict)
#   - `Bundle::Composite::Checksum`     — pure SHA-256 over (image_ids, layout)
#   - `Bundle::Composite::LayoutChooser`— member count → layout class dispatch
#   - `Bundle::Composite::Layout::*`    — six layout templates (libvips compose)
#
# `TileFetchError` surfaces non-200 responses from the IGDB CDN; the
# wrapping `BundleCoverBuild` Sidekiq job re-raises so retries fire.
class Bundle
  module Composite
    class Error < StandardError; end
    class TileFetchError < Error; end
  end
end
