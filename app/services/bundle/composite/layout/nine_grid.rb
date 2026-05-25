# DEPRECATED 2026-05-25 — no longer reachable via Bundle::Composite::LayoutChooser.
# 4+ game bundles now render via Bundle::Composite::Layout::CountOverflow.
# File retained for reference (NineGridWithOverflow delegates here); do not
# call from new code.
#
# Phase 14 §2 + Phase 27 §02 — NineGrid layout. Exactly 9 members;
# 3×3 grid, each tile 100×134. (100 × 3 = 300 width; 134 × 3 = 402,
# rounded to OUTPUT_HEIGHT 400 via the final crop.) The blank-cell
# helper survives because `NineGridWithOverflow` reuses this builder
# and may still pass nils in degenerate cases.
# Canvas halved 2026-05-17 — see `Bundle::Composite::Builder` header.
class Bundle
  module Composite
    module Layout
      module NineGrid
        OUTPUT_WIDTH  = 300
        OUTPUT_HEIGHT = 400
        TILE_W = 100
        TILE_H = 134  # 400 / 3 rounded up; final image cropped to 400
        ROWS = 3
        COLS = 3
        # Renamed 2026-05-17 from `CELLS` to free that constant name for
        # the ratios array below (consumed by `Bundle::Composite::CellMap`).
        CELL_COUNT = ROWS * COLS

        # Dark grey RGB used to fill blank slots and as the canvas
        # background for the final crop. Keeps the empty corner reading
        # as "intentional design" rather than a missing tile.
        BG_RGB = [ 30, 30, 30 ].freeze

        # Cell positions as 0..1 ratios — see `Bundle::Composite::CellMap`.
        # 3×3 grid. The libvips compose path uses 100×134 tiles (134×3 =
        # 402) and crops to 400, but the visual intent is clean thirds —
        # which is what the modal CSS generator wants. Row-major.
        THIRD = 1.0 / 3.0
        CELLS = [
          { x: 0.0,         y: 0.0,         w: THIRD, h: THIRD },
          { x: THIRD,       y: 0.0,         w: THIRD, h: THIRD },
          { x: 2.0 * THIRD, y: 0.0,         w: THIRD, h: THIRD },
          { x: 0.0,         y: THIRD,       w: THIRD, h: THIRD },
          { x: THIRD,       y: THIRD,       w: THIRD, h: THIRD },
          { x: 2.0 * THIRD, y: THIRD,       w: THIRD, h: THIRD },
          { x: 0.0,         y: 2.0 * THIRD, w: THIRD, h: THIRD },
          { x: THIRD,       y: 2.0 * THIRD, w: THIRD, h: THIRD },
          { x: 2.0 * THIRD, y: 2.0 * THIRD, w: THIRD, h: THIRD }
        ].freeze

        module_function

        def layout_name
          "nine_grid"
        end

        def cells
          CELLS
        end

        def compose(tiles, total_member_count: nil)
          raise ArgumentError, "expected 9 tiles, got #{tiles.size}" unless tiles.size == 9
          Bundle::Composite::Layout::NineGrid::Builder.new(tiles).build
        end

        # Internal builder — extracted so `NineGridWithOverflow` can
        # reuse the cell-placement logic and overlay text on top.
        class Builder
          def initialize(tiles)
            @tiles = tiles
          end

          def build
            cells = (0...CELL_COUNT).map do |i|
              tile = @tiles[i]
              if tile
                tile.thumbnail_image(TILE_W, height: TILE_H, crop: :centre)
              else
                blank_cell
              end
            end

            rows = (0...ROWS).map do |r|
              row_cells = cells[(r * COLS), COLS]
              row_cells.reduce { |acc, c| acc.join(c, :horizontal) }
            end

            stacked = rows.reduce { |acc, row| acc.join(row, :vertical) }
            # Crop to canonical 300×400 (band-and-format to JPEG-safe RGB).
            stacked.crop(0, 0, OUTPUT_WIDTH, OUTPUT_HEIGHT)
          end

          private

          def blank_cell
            Vips::Image.black(TILE_W, TILE_H).new_from_image(BG_RGB)
          end
        end
      end
    end
  end
end
