# Phase 14 §2 — Pair layout. 2 members; side by side, each 300×800.
module Composite
  module Layout
    module Pair
      OUTPUT_WIDTH  = 600
      OUTPUT_HEIGHT = 800
      TILE_W = 300
      TILE_H = 800

      module_function

      def layout_name
        "pair"
      end

      def compose(tiles, total_member_count: nil)
        raise ArgumentError, "expected 2 tiles, got #{tiles.size}" unless tiles.size == 2
        left  = tiles[0].thumbnail_image(TILE_W, height: TILE_H, crop: :centre)
        right = tiles[1].thumbnail_image(TILE_W, height: TILE_H, crop: :centre)
        left.join(right, :horizontal)
      end
    end
  end
end
