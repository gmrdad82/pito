# Phase 27 §02 — Netflix5 layout. 5 members; 1 big left + 2×2 grid right.
#
# Canvas 300×400 (matches every other layout in this dir; the spec
# expresses the same shape at the 98×130 shelf variant and the
# proportions scale 1:1). Canvas halved 2026-05-17 — see
# `Bundle::Composite::Builder` header.
#
# Pixel decomposition:
#
#   left      → 150 × 400 (full height, left half)
#   right col → 150 wide, split into a 2×2 grid of 75×200 cells:
#                 r0c0 75×200    r0c1 75×200
#                 r1c0 75×200    r1c1 75×200
#   column sums: 150 + (75+75) = 300 ✓
#   row sums   : left 400; right (200+200) = 400 ✓
#
# Spec note: spec §02 describes the right cells as 24/25 × 65/65 at
# the 98×130 shelf size to absorb rounding. At 300×400 the right
# column divides cleanly into 75+75 × 200+200, so the rounding-
# remainder split is unnecessary.
class Bundle
  module Composite
    module Layout
      module Netflix5
        OUTPUT_WIDTH  = 300
        OUTPUT_HEIGHT = 400
        LEFT_W        = 150
        LEFT_H        = 400
        RIGHT_CELL_W  = 75
        RIGHT_CELL_H  = 200

        # Cell positions as 0..1 ratios — see `Bundle::Composite::CellMap`.
        #   [0] left big   → 150 × 400 → x 0..0.5, y 0..1
        #   [1] r0c0       →  75 × 200 → x 0.5..0.75, y 0..0.5
        #   [2] r0c1       →  75 × 200 → x 0.75..1.0, y 0..0.5
        #   [3] r1c0       →  75 × 200 → x 0.5..0.75, y 0.5..1.0
        #   [4] r1c1       →  75 × 200 → x 0.75..1.0, y 0.5..1.0
        CELLS = [
          { x: 0.0,  y: 0.0, w: 0.5,  h: 1.0 },
          { x: 0.5,  y: 0.0, w: 0.25, h: 0.5 },
          { x: 0.75, y: 0.0, w: 0.25, h: 0.5 },
          { x: 0.5,  y: 0.5, w: 0.25, h: 0.5 },
          { x: 0.75, y: 0.5, w: 0.25, h: 0.5 }
        ].freeze

        module_function

        def layout_name
          "netflix5"
        end

        def cells
          CELLS
        end

        def compose(tiles, total_member_count: nil)
          raise ArgumentError, "expected 5 tiles, got #{tiles.size}" unless tiles.size == 5

          left = tiles[0].thumbnail_image(LEFT_W, height: LEFT_H, crop: :centre)

          right_cells = tiles[1..4].map do |t|
            t.thumbnail_image(RIGHT_CELL_W, height: RIGHT_CELL_H, crop: :centre)
          end

          right_top = right_cells[0].join(right_cells[1], :horizontal)
          right_bot = right_cells[2].join(right_cells[3], :horizontal)
          right_col = right_top.join(right_bot, :vertical)

          left.join(right_col, :horizontal)
        end
      end
    end
  end
end
