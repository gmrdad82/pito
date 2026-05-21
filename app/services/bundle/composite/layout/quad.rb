# Phase 14 §2 — Quad layout. 4 members; 2×2 grid, each tile 150×200.
# Canvas halved 2026-05-17 — see `Bundle::Composite::Builder` header.
class Bundle
  module Composite
    module Layout
      module Quad
        OUTPUT_WIDTH  = 300
        OUTPUT_HEIGHT = 400
        TILE_W = 150
        TILE_H = 200

        # Cell positions as 0..1 ratios — see `Bundle::Composite::CellMap`.
        # 2×2 grid of 150×200 tiles. Row-major: [0]=TL [1]=TR [2]=BL [3]=BR.
        CELLS = [
          { x: 0.0, y: 0.0, w: 0.5, h: 0.5 },
          { x: 0.5, y: 0.0, w: 0.5, h: 0.5 },
          { x: 0.0, y: 0.5, w: 0.5, h: 0.5 },
          { x: 0.5, y: 0.5, w: 0.5, h: 0.5 }
        ].freeze

        module_function

        def layout_name
          "quad"
        end

        def cells
          CELLS
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
end
