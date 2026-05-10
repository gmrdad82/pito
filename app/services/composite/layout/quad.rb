# Phase 14 §2 — Quad layout. 4 members; 2×2 grid, each tile 300×400.
module Composite
  module Layout
    module Quad
      OUTPUT_WIDTH  = 600
      OUTPUT_HEIGHT = 800
      TILE_W = 300
      TILE_H = 400

      module_function

      def layout_name
        "quad"
      end

      def compose(tiles, total_member_count: nil)
        raise ArgumentError, "expected 4 tiles, got #{tiles.size}" unless tiles.size == 4
        resized = tiles.map { |t| t.thumbnail_image(TILE_W, height: TILE_H, crop: :centre) }
        top_row = resized[0].join(resized[1], :horizontal)
        bot_row = resized[2].join(resized[3], :horizontal)
        top_row.join(bot_row, :vertical)
      end
    end
  end
end
