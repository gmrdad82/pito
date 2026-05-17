# Phase 14 §2 — Netflix layout. 3 members; left tile 150×400 (large),
# right column two stacked tiles 150×200 each.
# Canvas halved 2026-05-17 — see `Composite::Builder` header.
module Composite
  module Layout
    module Netflix
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400
      LEFT_W  = 150
      LEFT_H  = 400
      RIGHT_W = 150
      RIGHT_H = 200

      # Cell positions as 0..1 ratios — see `Composite::CellMap`.
      #   [0] left big   → 150 × 400 → 0.5 × 1.0
      #   [1] right top  → 150 × 200 → 0.5 × 0.5
      #   [2] right bot  → 150 × 200 → 0.5 × 0.5
      CELLS = [
        { x: 0.0, y: 0.0, w: 0.5, h: 1.0 },
        { x: 0.5, y: 0.0, w: 0.5, h: 0.5 },
        { x: 0.5, y: 0.5, w: 0.5, h: 0.5 }
      ].freeze

      module_function

      def layout_name
        "netflix"
      end

      def cells
        CELLS
      end

      def compose(tiles, total_member_count: nil)
        raise ArgumentError, "expected 3 tiles, got #{tiles.size}" unless tiles.size == 3
        left      = tiles[0].thumbnail_image(LEFT_W, height: LEFT_H, crop: :centre)
        right_top = tiles[1].thumbnail_image(RIGHT_W, height: RIGHT_H, crop: :centre)
        right_bot = tiles[2].thumbnail_image(RIGHT_W, height: RIGHT_H, crop: :centre)
        right_col = right_top.join(right_bot, :vertical)
        left.join(right_col, :horizontal)
      end
    end
  end
end
