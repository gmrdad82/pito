# Phase 27 §02 — EightGrid layout. 8 members; 2 columns × 4 rows.
#
# Canvas 300×400. Canvas halved 2026-05-17 — see `Composite::Builder`
# header. Spec §02 expresses this at the 98×130 shelf variant as
# 49×32 cells with the last row absorbing the 130-rounding remainder
# (32+32+32+34=130). At 300×400 the layout divides cleanly:
#
#   columns → 150 / 150 (sums to 300)
#   rows    → 100 / 100 / 100 / 100 (sums to 400)
#   each cell → 150 × 100
module Composite
  module Layout
    module EightGrid
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400
      TILE_W        = 150
      TILE_H        = 100
      ROWS          = 4
      COLS          = 2

      module_function

      def layout_name
        "eight_grid"
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
