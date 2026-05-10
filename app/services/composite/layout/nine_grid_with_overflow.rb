# Phase 14 §2 — NineGridWithOverflow layout. 10+ members; 3×3 grid
# (same as NineGrid) with the bottom-right tile overlaid with a "+N"
# caption, where N = total_member_count - 8. Caption format per master
# decision is just the number (e.g. "+2"), no "more" / "and" prefix.
module Composite
  module Layout
    module NineGridWithOverflow
      OUTPUT_WIDTH  = Composite::Layout::NineGrid::OUTPUT_WIDTH
      OUTPUT_HEIGHT = Composite::Layout::NineGrid::OUTPUT_HEIGHT
      TILE_W = Composite::Layout::NineGrid::TILE_W
      TILE_H = Composite::Layout::NineGrid::TILE_H

      # Where the overlay text sits relative to the bottom-right cell
      # (cell origin = (400, 533) given 200 / 267 cell shape).
      OVERLAY_OPACITY = 0.55  # 0..1, applied to a black scrim
      TEXT_DPI = 200
      TEXT_FONT = "sans-serif bold 64"

      module_function

      def layout_name
        "nine_grid_with_overflow"
      end

      def compose(tiles, total_member_count: nil)
        if tiles.size != 9
          raise ArgumentError, "expected exactly 9 tiles for overflow layout, got #{tiles.size}"
        end

        overflow_n = total_member_count.to_i - 8
        # Defensive: if caller passes the wrong count the worst case
        # is a "+0" overlay, not a crash.
        overflow_n = 1 if overflow_n <= 0

        base = Composite::Layout::NineGrid::Builder.new(tiles).build
        overlay_overflow_caption(base, overflow_n)
      end

      def overlay_overflow_caption(base, overflow_n)
        # Bottom-right cell origin in the 600×800 canvas.
        cell_x = (Composite::Layout::NineGrid::COLS - 1) * TILE_W
        cell_y = (Composite::Layout::NineGrid::ROWS - 1) * TILE_H

        # Black scrim at OVERLAY_OPACITY over the bottom-right cell.
        scrim = Vips::Image.black(TILE_W, TILE_H)
                          .new_from_image([ 0, 0, 0 ])
                          .bandjoin(Vips::Image.black(TILE_W, TILE_H)
                                          .new_from_image([ (255 * OVERLAY_OPACITY).to_i ]))
        scrimmed = base.composite2(scrim, :over, x: cell_x, y: cell_y)

        # Render "+N" text and composite over the scrimmed cell. libvips
        # `text` returns a single-band image; we colorize white + alpha.
        text_image = Vips::Image.text("+#{overflow_n}", dpi: TEXT_DPI, font: TEXT_FONT)
        # Centre the text inside the cell.
        text_x = cell_x + ((TILE_W - text_image.width) / 2)
        text_y = cell_y + ((TILE_H - text_image.height) / 2)
        # Build a white-with-alpha RGBA image: each band = 255 except
        # alpha which equals the rendered text image (a coverage mask).
        white = text_image.new_from_image([ 255, 255, 255 ])
        rgba_text = white.bandjoin(text_image)
        scrimmed.composite2(rgba_text, :over, x: text_x, y: text_y)
      end
    end
  end
end
