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

      module_function

      def layout_name
        "netflix"
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
