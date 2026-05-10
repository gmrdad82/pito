# Phase 14 §2 — Single layout. 1 member; resize to fill 600×800.
module Composite
  module Layout
    module Single
      OUTPUT_WIDTH  = 600
      OUTPUT_HEIGHT = 800

      module_function

      def layout_name
        "single"
      end

      def compose(tiles, total_member_count: nil)
        raise ArgumentError, "expected 1 tile, got #{tiles.size}" unless tiles.size == 1
        tiles[0].thumbnail_image(OUTPUT_WIDTH, height: OUTPUT_HEIGHT, crop: :centre)
      end
    end
  end
end
