# Phase 14 §2 — Single layout. 1 member; resize to fill 300×400.
# Canvas halved 2026-05-17 — see `Composite::Builder` header.
module Composite
  module Layout
    module Single
      OUTPUT_WIDTH  = 300
      OUTPUT_HEIGHT = 400

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
