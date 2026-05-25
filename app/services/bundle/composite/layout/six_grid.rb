# DEPRECATED 2026-05-25 — no longer reachable via Bundle::Composite::LayoutChooser.
# 4+ game bundles now render via Bundle::Composite::Layout::CountOverflow.
# File retained for reference; do not call from new code.
#
# Phase 27 §02 — SixGrid layout. 6 members; 3 columns × 2 rows.
#
# Canvas 300×400. Canvas halved 2026-05-17 — see `Bundle::Composite::Builder`
# header. Spec §02 expresses the same shape at the 98×130 shelf
# variant as 33+33+32 × 65+65; at 300×400 the layout divides
# cleanly into 100+100+100 × 200+200.
#
#   columns → 100 / 100 / 100 (sums to 300)
#   rows    → 200 / 200       (sums to 400)
#   each cell → 100 × 200
class Bundle
  module Composite
    module Layout
      module SixGrid
        OUTPUT_WIDTH  = 300
        OUTPUT_HEIGHT = 400
        TILE_W        = 100
        TILE_H        = 200
        ROWS          = 2
        COLS          = 3

        # Cell positions as 0..1 ratios — see `Bundle::Composite::CellMap`.
        # 3 columns × 2 rows of 100×200 tiles. Row-major.
        # Columns: 0, 1/3, 2/3 with width 1/3 each.
        # Rows: 0, 0.5 with height 0.5 each.
        THIRD = 1.0 / 3.0
        CELLS = [
          { x: 0.0,         y: 0.0, w: THIRD, h: 0.5 },
          { x: THIRD,       y: 0.0, w: THIRD, h: 0.5 },
          { x: 2.0 * THIRD, y: 0.0, w: THIRD, h: 0.5 },
          { x: 0.0,         y: 0.5, w: THIRD, h: 0.5 },
          { x: THIRD,       y: 0.5, w: THIRD, h: 0.5 },
          { x: 2.0 * THIRD, y: 0.5, w: THIRD, h: 0.5 }
        ].freeze

        module_function

        def layout_name
          "six_grid"
        end

        def cells
          CELLS
        end

        def compose(tiles, total_member_count: nil)
          raise ArgumentError, "expected 6 tiles, got #{tiles.size}" unless tiles.size == 6

          resized = tiles.map { |t| t.thumbnail_image(TILE_W, height: TILE_H, crop: :centre) }

          top_row = resized[0..2].reduce { |acc, c| acc.join(c, :horizontal) }
          bot_row = resized[3..5].reduce { |acc, c| acc.join(c, :horizontal) }

          top_row.join(bot_row, :vertical)
        end
      end
    end
  end
end
