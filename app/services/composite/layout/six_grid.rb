# Phase 27 §02 — SixGrid layout. 6 members; 3 columns × 2 rows.
#
# Canvas 300×400. Canvas halved 2026-05-17 — see `Composite::Builder`
# header. Spec §02 expresses the same shape at the 98×130 shelf
# variant as 33+33+32 × 65+65; at 300×400 the layout divides
# cleanly into 100+100+100 × 200+200.
#
#   columns → 100 / 100 / 100 (sums to 300)
#   rows    → 200 / 200       (sums to 400)
#   each cell → 100 × 200
module Composite
  module Layout
    module SixGrid
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400
      TILE_W        = 100
      TILE_H        = 200
      ROWS          = 2
      COLS          = 3

      module_function

      def layout_name
        "six_grid"
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
