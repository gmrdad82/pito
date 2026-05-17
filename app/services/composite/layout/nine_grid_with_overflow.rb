# Identical to :nine_grid layout output. The +N overflow indicator is
# rendered as an HTML overlay in `_bundle_for_shelf_tile.html.erb`, not
# baked into the JPEG. The layout file survives as a separate class so
# the chooser can dispatch N>=10 distinctly (for the HTML view to
# compute overflow_n).
module Composite
  module Layout
    module NineGridWithOverflow
      OUTPUT_WIDTH  = Composite::Layout::NineGrid::OUTPUT_WIDTH
      OUTPUT_HEIGHT = Composite::Layout::NineGrid::OUTPUT_HEIGHT
      TILE_W = Composite::Layout::NineGrid::TILE_W
      TILE_H = Composite::Layout::NineGrid::TILE_H

      module_function

      def layout_name
        "nine_grid_with_overflow"
      end

      def compose(tiles, total_member_count: nil)
        if tiles.size != 9
          raise ArgumentError, "expected exactly 9 tiles for overflow layout, got #{tiles.size}"
        end

        # `total_member_count` is kept in the signature so the builder
        # call site does not change, but is unused here — the overflow
        # indicator now lives in the HTML view layer, not the JPEG.
        _ = total_member_count

        Composite::Layout::NineGrid::Builder.new(tiles).build
      end
    end
  end
end
