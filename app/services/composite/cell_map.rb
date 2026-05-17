# 2026-05-17 — Composite::CellMap.
#
# Single source of truth for "where do the cover tiles sit on the
# 0..1 unit square?" for a given member count. Used by the bundle-
# modal CSS generator (and any other consumer that needs to mirror
# the composite layout in HTML/CSS). The libvips JPEG builder still
# uses its own pixel constants — both surfaces now derive from the
# same per-layout `cells` arrays defined on each
# `Composite::Layout::*` module, so when one is edited the other
# follows for free.
#
# Each cell is a hash with `:x`, `:y`, `:w`, `:h` floats in 0..1 and
# a `:corners` array of symbols enumerating which OUTSIDE corners
# of the composite this cell touches — any of `:top_left`,
# `:top_right`, `:bottom_left`, `:bottom_right`. Cells that sit on
# an edge (e.g. top-middle of a 3×3 grid) but not at a CORNER of
# the unit square return an empty `:corners` array. The view layer
# uses this to round only the four outer corners of the composite,
# not every edge tile.
#
# A SINGLE-cell layout (Layout::Single — one tile filling the whole
# unit square) hits all four corner conditions, so the lone cell
# gets all four corners rounded — yielding a wholly rounded card,
# which is the correct visual for a 1-game bundle.
#
# Cells are returned in render order (tile 0 is the first member,
# tile 1 the second, etc.). The +N overflow badge is NOT a cell —
# it is overlaid on the bottom-right tile by the view layer.
#
# Empty array is returned when count is non-positive (defensive —
# `LayoutChooser` raises in that case, so callers should generally
# guard upstream).
module Composite
  module CellMap
    module_function

    # Epsilon for float comparison against 0 / 1 unit-square edges.
    # The layout CELLS arrays use exact `1.0/3.0` thirds (and other
    # simple fractions), so the sum `x + w` at the right edge lands
    # within ~1e-15 of 1.0 — a generous 1e-6 tolerance is safe.
    EPSILON = 1e-6

    def for(count)
      return [] unless count.is_a?(Integer) && count.positive?

      raw_cells = Composite::LayoutChooser.choose(count).cells
      raw_cells.map { |cell| decorate(cell) }
    end

    # Decorate a single cell hash with a `:corners` array enumerating
    # which OUTSIDE corners of the unit-square composite this cell
    # touches. A cell can touch 0, 1, 2, or (for Single) 4 corners.
    def decorate(cell)
      x = cell[:x].to_f
      y = cell[:y].to_f
      w = cell[:w].to_f
      h = cell[:h].to_f

      left   = x.abs < EPSILON
      top    = y.abs < EPSILON
      right  = (x + w - 1.0).abs < EPSILON
      bottom = (y + h - 1.0).abs < EPSILON

      corners = []
      corners << :top_left     if left && top
      corners << :top_right    if right && top
      corners << :bottom_left  if left && bottom
      corners << :bottom_right if right && bottom

      cell.merge(corners: corners.freeze)
    end
  end
end
