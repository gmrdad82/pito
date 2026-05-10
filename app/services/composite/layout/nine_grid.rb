# Phase 14 §2 — NineGrid layout. 5..9 members; 3×3 grid, each tile
# 200×267. Empty cells are filled with a flat dark-grey background.
# (200 × 3 = 600 width; 267 × 3 = 801, rounded to OUTPUT_HEIGHT 800
# via the final crop.)
module Composite
  module Layout
    module NineGrid
      OUTPUT_WIDTH  = 600
      OUTPUT_HEIGHT = 800
      TILE_W = 200
      TILE_H = 267  # 800 / 3 rounded up; final image cropped to 800
      ROWS = 3
      COLS = 3
      CELLS = ROWS * COLS

      # Dark grey RGB used to fill blank slots and as the canvas
      # background for the final crop. Keeps the empty corner reading
      # as "intentional design" rather than a missing tile.
      BG_RGB = [ 30, 30, 30 ].freeze

      module_function

      def layout_name
        "nine_grid"
      end

      def compose(tiles, total_member_count: nil)
        if tiles.size < 5 || tiles.size > 9
          raise ArgumentError, "expected 5..9 tiles, got #{tiles.size}"
        end
        Composite::Layout::NineGrid::Builder.new(tiles).build
      end

      # Internal builder — extracted so `NineGridWithOverflow` can
      # reuse the cell-placement logic and overlay text on top.
      class Builder
        def initialize(tiles)
          @tiles = tiles
        end

        def build
          cells = (0...CELLS).map do |i|
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
          # Crop to canonical 600×800 (band-and-format to JPEG-safe RGB).
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
