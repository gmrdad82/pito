# Phase 14 §2 — Composite cover module namespace.
#
# Houses the bundle composite-cover builder pipeline:
#   - `Composite::Builder`      — orchestrates the build
#   - `Composite::TileCache`    — IGDB CDN tile cache (download + evict)
#   - `Composite::Checksum`     — pure SHA-256 over (image_ids, layout)
#   - `Composite::LayoutChooser`— member count → layout class dispatch
#   - `Composite::Layout::*`    — six layout templates (libvips compose)
#
# `TileFetchError` surfaces non-200 responses from the IGDB CDN; the
# wrapping `BundleCoverBuild` Sidekiq job re-raises so retries fire.
module Composite
  class Error < StandardError; end
  class TileFetchError < Error; end
end
