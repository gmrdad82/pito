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
# Each cell is a hash with `:x`, `:y`, `:w`, `:h` floats in 0..1
# (top-left origin, unit-square coordinates).
#
# Cells are returned in render order (tile 0 is the first member,
# tile 1 the second, etc.). The +N overflow badge is NOT a cell —
# it is overlaid on the bottom-right tile by the view layer.
#
# Empty array is returned when count is non-positive (defensive —
# `LayoutChooser` raises in that case, so callers should generally
# guard upstream).
#
# 2026-05-18 — the previous per-cell `:corners` decoration (which
# enumerated which outside corners of the unit square a cell
# touched, used for selective corner rounding) was removed when the
# bundle modal switched to a full 2px radius on every cell. No
# consumer needs corner metadata today; layouts return raw cells.
module Composite
  module CellMap
    module_function

    def for(count)
      return [] unless count.is_a?(Integer) && count.positive?

      Composite::LayoutChooser.choose(count).cells
    end
  end
end
