# Phase 14 §2 — Single layout. 1 member; resize to fill 300×400.
# Canvas halved 2026-05-17 — see `Composite::Builder` header.
module Composite
  module Layout
    module Single
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400

      # Cell positions as 0..1 ratios of the canvas. Shared by the
      # libvips JPEG builder (via OUTPUT_WIDTH × OUTPUT_HEIGHT scaling
      # — currently still using its own pixel constants) and the
      # bundle-modal CSS generator. See `Composite::CellMap`.
      CELLS = [
        { x: 0.0, y: 0.0, w: 1.0, h: 1.0 }
      ].freeze

      module_function

      def layout_name
        "single"
      end

      def cells
        CELLS
      end

      def compose(tiles, total_member_count: nil)
        raise ArgumentError, "expected 1 tile, got #{tiles.size}" unless tiles.size == 1
        tiles[0].thumbnail_image(OUTPUT_WIDTH, height: OUTPUT_HEIGHT, crop: :centre)
      end
    end
  end
end
