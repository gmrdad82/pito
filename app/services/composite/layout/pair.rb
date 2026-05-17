# Phase 14 §2 — Pair layout. 2 members; side by side, each 150×400.
# Canvas halved 2026-05-17 — see `Composite::Builder` header.
module Composite
  module Layout
    module Pair
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400
      TILE_W = 150
      TILE_H = 400

      # Cell positions as 0..1 ratios — see `Composite::CellMap`.
      # Two equal halves: 150/300 wide, full 400 tall.
      CELLS = [
        { x: 0.0, y: 0.0, w: 0.5, h: 1.0 },
        { x: 0.5, y: 0.0, w: 0.5, h: 1.0 }
      ].freeze

      module_function

      def layout_name
        "pair"
      end

      def cells
        CELLS
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
