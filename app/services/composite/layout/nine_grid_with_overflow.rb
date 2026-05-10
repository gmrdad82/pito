# Phase 14 §2 — NineGridWithOverflow layout. 10+ members; 3×3 grid
# (same as NineGrid) with the bottom-right tile overlaid with a "+N"
# caption, where N = total_member_count - 8. Caption format per master
# decision is just the number (e.g. "+2"), no "more" / "and" prefix.
#
# Implementation note: libvips' colour-space routing rejects raw
# multiband images, so we keep all working images in :srgb /
# :b_w via `cast` + `copy(interpretation:)`. The overlay is built as
# a 4-band sRGB+alpha image and composited via `composite2` which
# handles the alpha blend.
module Composite
  module Layout
    module NineGridWithOverflow
      OUTPUT_WIDTH  = Composite::Layout::NineGrid::OUTPUT_WIDTH
      OUTPUT_HEIGHT = Composite::Layout::NineGrid::OUTPUT_HEIGHT
      TILE_W = Composite::Layout::NineGrid::TILE_W
      TILE_H = Composite::Layout::NineGrid::TILE_H

      OVERLAY_OPACITY = 160 # 0..255 alpha applied to the black scrim
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
        # is a "+1" overlay, not a crash.
        overflow_n = 1 if overflow_n <= 0

        base = Composite::Layout::NineGrid::Builder.new(tiles).build
        overlay_overflow_caption(base, overflow_n)
      end

      def overlay_overflow_caption(base, overflow_n)
        # Bottom-right cell origin in the 600×800 canvas.
        cell_x = (Composite::Layout::NineGrid::COLS - 1) * TILE_W
        cell_y = (Composite::Layout::NineGrid::ROWS - 1) * TILE_H

        # Build a 4-band sRGB+alpha overlay image at TILE_W × TILE_H.
        # Black RGB; alpha = OVERLAY_OPACITY everywhere except where
        # the rendered "+N" text increases coverage (text mask is
        # composited on top of the scrim, then we layer the white
        # text over it).
        overlay = build_overflow_overlay(overflow_n)
        base.composite2(overlay, :over, x: cell_x, y: cell_y)
      end

      def build_overflow_overlay(overflow_n)
        # 1. Black scrim with constant alpha.
        scrim_rgb   = Vips::Image.black(TILE_W, TILE_H, bands: 3) # 3-band black
        scrim_alpha = Vips::Image.black(TILE_W, TILE_H) + OVERLAY_OPACITY
        scrim       = scrim_rgb.bandjoin(scrim_alpha)
                              .copy(interpretation: :srgb)

        # 2. Render "+N" text. `Vips::Image.text` returns an 8-bit
        # single-band coverage mask; we lift it to a 4-band white-RGBA
        # image so it can sit on top of the scrim.
        text_mask = Vips::Image.text("+#{overflow_n}",
                                     dpi: TEXT_DPI, font: TEXT_FONT)
        text_w = text_mask.width
        text_h = text_mask.height

        # White RGB matching the text mask's footprint.
        white_rgb = Vips::Image.black(text_w, text_h, bands: 3) + 255
        text_image = white_rgb.bandjoin(text_mask)
                              .copy(interpretation: :srgb)

        # 3. Composite the text onto the scrim, centred.
        text_x = (TILE_W - text_w) / 2
        text_y = (TILE_H - text_h) / 2
        scrim.composite2(text_image, :over, x: text_x, y: text_y)
      end
    end
  end
end
