# Identical to :nine_grid layout output. The +N overflow indicator is
# rendered as an HTML overlay in `_bundle_for_shelf_tile.html.erb`, not
# baked into the JPEG. The layout file survives as a separate class so
# the chooser can dispatch N>=10 distinctly (for the HTML view to
# compute overflow_n).
class Bundle
  module Composite
    module Layout
      module NineGridWithOverflow
        OUTPUT_WIDTH  = Bundle::Composite::Layout::NineGrid::OUTPUT_WIDTH
        OUTPUT_HEIGHT = Bundle::Composite::Layout::NineGrid::OUTPUT_HEIGHT
        TILE_W = Bundle::Composite::Layout::NineGrid::TILE_W
        TILE_H = Bundle::Composite::Layout::NineGrid::TILE_H

        # Cell positions as 0..1 ratios — see `Bundle::Composite::CellMap`.
        # Geometry is identical to NineGrid (the +N badge is an HTML
        # overlay, not a cell). Delegate to the canonical 9-cell array
        # so a future change to either layout stays in one place.
        CELLS = Bundle::Composite::Layout::NineGrid::CELLS

        module_function

        def layout_name
          "nine_grid_with_overflow"
        end

        def cells
          CELLS
        end

        def compose(tiles, total_member_count: nil)
          if tiles.size != 9
            raise ArgumentError, "expected exactly 9 tiles for overflow layout, got #{tiles.size}"
          end

          # `total_member_count` is kept in the signature so the builder
          # call site does not change, but is unused here — the overflow
          # indicator now lives in the HTML view layer, not the JPEG.
          _ = total_member_count

          Bundle::Composite::Layout::NineGrid::Builder.new(tiles).build
        end
      end
    end
  end
end
