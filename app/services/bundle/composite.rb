# Phase 14 §2 — Bundle::Composite cover module namespace.
# 2026-05-25 — layout set simplified to 4 paths (single/pair/netflix/count_overflow).
#
# Houses the bundle composite-cover builder pipeline:
#   - `Bundle::Composite::Builder`      — orchestrates the build
#   - `Bundle::Composite::TileCache`    — IGDB CDN tile cache (download + evict)
#   - `Bundle::Composite::Checksum`     — pure SHA-256 over (image_ids, layout)
#   - `Bundle::Composite::LayoutChooser`— member count → layout class dispatch
#   - `Bundle::Composite::Layout::*`    — four active layout templates (libvips)
#
# Active layouts:
#   1   → Layout::Single       — resize to fill 300×400
#   2   → Layout::Pair         — side-by-side halves
#   3   → Layout::Netflix      — 1 big left + 2-row right
#   4+  → Layout::CountOverflow— solid games-accent rect + centered count numeral
#
# Deprecated (retained in code, not routed by LayoutChooser):
#   Layout::Quad, Layout::Netflix5, Layout::SixGrid, Layout::Netflix7,
#   Layout::EightGrid, Layout::NineGrid, Layout::NineGridWithOverflow
#
# `TileFetchError` surfaces non-200 responses from the IGDB CDN; the
# wrapping `BundleCoverBuild` Sidekiq job re-raises so retries fire.
class Bundle
  module Composite
    class Error < StandardError; end
    class TileFetchError < Error; end
  end
end
