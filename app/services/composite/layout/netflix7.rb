# Phase 27 §02 — Netflix7 layout. 7 members; 1 big top + 3 mid row +
# 3 bottom row.
#
# Canvas 300×400. Canvas halved 2026-05-17 — see `Composite::Builder`
# header. Spec §02 expresses this at the 98×130 shelf variant as:
#
#   big top  → 98 × 65
#   mid row  → 33×32 / 33×32 / 32×32
#   bot row  → 33×33 / 33×33 / 32×33
#
# At 300×400 the dimensions divide cleanly without the 32/33
# remainder-absorption split:
#
#   big top  → 300 × 200 (full width, top half)
#   mid row  → 100 × 100 / 100 × 100 / 100 × 100 (sums to 300)
#   bot row  → 100 × 100 / 100 × 100 / 100 × 100 (sums to 300)
#   total height → 200 + 100 + 100 = 400 ✓
module Composite
  module Layout
    module Netflix7
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400
      BIG_W         = 300
      BIG_H         = 200
      CELL_W        = 100
      CELL_H        = 100

      # Cell positions as 0..1 ratios — see `Composite::CellMap`.
      #   [0] big top    → 300 × 200 → full width, top half
      #   [1..3] mid row → 100 × 100 each, y 0.5..0.75
      #   [4..6] bot row → 100 × 100 each, y 0.75..1.0
      # Vertical band sizing: 0.5 / 0.25 / 0.25 (sums to 1.0).
      THIRD = 1.0 / 3.0
      CELLS = [
        { x: 0.0,         y: 0.0,  w: 1.0,   h: 0.5  },
        { x: 0.0,         y: 0.5,  w: THIRD, h: 0.25 },
        { x: THIRD,       y: 0.5,  w: THIRD, h: 0.25 },
        { x: 2.0 * THIRD, y: 0.5,  w: THIRD, h: 0.25 },
        { x: 0.0,         y: 0.75, w: THIRD, h: 0.25 },
        { x: THIRD,       y: 0.75, w: THIRD, h: 0.25 },
        { x: 2.0 * THIRD, y: 0.75, w: THIRD, h: 0.25 }
      ].freeze

      module_function

      def layout_name
        "netflix7"
      end

      def cells
        CELLS
      end

      def compose(tiles, total_member_count: nil)
        raise ArgumentError, "expected 7 tiles, got #{tiles.size}" unless tiles.size == 7

        big = tiles[0].thumbnail_image(BIG_W, height: BIG_H, crop: :centre)

        small_cells = tiles[1..6].map do |t|
          t.thumbnail_image(CELL_W, height: CELL_H, crop: :centre)
        end

        mid_row = small_cells[0..2].reduce { |acc, c| acc.join(c, :horizontal) }
        bot_row = small_cells[3..5].reduce { |acc, c| acc.join(c, :horizontal) }

        big.join(mid_row, :vertical).join(bot_row, :vertical)
      end
    end
  end
end
