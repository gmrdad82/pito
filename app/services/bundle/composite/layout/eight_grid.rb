# DEPRECATED 2026-05-25 — no longer reachable via Bundle::Composite::LayoutChooser.
# 4+ game bundles now render via Bundle::Composite::Layout::CountOverflow.
# File retained for reference; do not call from new code.
#
# Phase 27 §02 — EightGrid layout. 8 members; 2 columns × 4 rows.
#
# Canvas 300×400. Canvas halved 2026-05-17 — see `Bundle::Composite::Builder`
# header. Spec §02 expresses this at the 98×130 shelf variant as
# 49×32 cells with the last row absorbing the 130-rounding remainder
# (32+32+32+34=130). At 300×400 the layout divides cleanly:
#
#   columns → 150 / 150 (sums to 300)
#   rows    → 100 / 100 / 100 / 100 (sums to 400)
#   each cell → 150 × 100
class Bundle
  module Composite
    module Layout
      module EightGrid
        OUTPUT_WIDTH  = 300
        OUTPUT_HEIGHT = 400
        TILE_W        = 150
        TILE_H        = 100
        ROWS          = 4
        COLS          = 2

        # Cell positions as 0..1 ratios — see `Bundle::Composite::CellMap`.
        # 2 columns × 4 rows of 150×100 tiles. Row-major.
        # Columns: 0, 0.5 with width 0.5 each.
        # Rows: 0, 0.25, 0.5, 0.75 with height 0.25 each.
        CELLS = [
          { x: 0.0, y: 0.0,  w: 0.5, h: 0.25 },
          { x: 0.5, y: 0.0,  w: 0.5, h: 0.25 },
          { x: 0.0, y: 0.25, w: 0.5, h: 0.25 },
          { x: 0.5, y: 0.25, w: 0.5, h: 0.25 },
          { x: 0.0, y: 0.5,  w: 0.5, h: 0.25 },
          { x: 0.5, y: 0.5,  w: 0.5, h: 0.25 },
          { x: 0.0, y: 0.75, w: 0.5, h: 0.25 },
          { x: 0.5, y: 0.75, w: 0.5, h: 0.25 }
        ].freeze

        module_function

        def layout_name
          "eight_grid"
        end

        def cells
          CELLS
        end

        def compose(tiles, total_member_count: nil)
          raise ArgumentError, "expected 8 tiles, got #{tiles.size}" unless tiles.size == 8

          resized = tiles.map { |t| t.thumbnail_image(TILE_W, height: TILE_H, crop: :centre) }

          rows = (0...ROWS).map do |r|
            left  = resized[r * COLS]
            right = resized[(r * COLS) + 1]
            left.join(right, :horizontal)
          end

          rows.reduce { |acc, row| acc.join(row, :vertical) }
        end
      end
    end
  end
end
