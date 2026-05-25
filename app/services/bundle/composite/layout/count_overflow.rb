# 2026-05-25 — CountOverflow layout. 4+ members; renders a 300×400 solid
# accent-colored rectangle with the member count as a large centered numeral.
#
# Purpose: replaces the now-deprecated Quad/Netflix5/SixGrid/Netflix7/
# EightGrid/NineGrid/NineGridWithOverflow paths for bundles with 4 or more
# games. Rather than rendering tiny unreadable game covers at high counts,
# this layout communicates "how many" clearly and cheaply.
#
# Output: 300×400 JPEG (same canvas as all other layouts in this dir).
# Background color: games section accent (#7eb6ff — Pale Cobalt) from
# `Pito::Theme::Sections::ACCENT["games"]`.
# Text color: Dracula background (#282a36) for contrast on the light accent.
# Font: libvips built-in "sans bold". Size tuned so 1–3 digit counts fill
# ~60% of the canvas height without clipping at 300px wide.
#
# Rendering technique: libvips `Vips::Image.text` to rasterize the numeral,
# then embed it centered on a solid-color canvas via `composite2`. Matches
# the libvips technique used in the sibling layouts (thumbnail_image / join).
# No ImageMagick, no external font files required — libvips ships Pango.
#
# Kwargs:
#   tiles              — ignored (must be empty Array; validated)
#   total_member_count — the integer to display (required)
#
# Variants: none — always the same solid rectangle + numeral.
# Focusables: none (composite JPEG, not interactive).
# Cable subscriptions: none.
# Related: Bundle::Composite::LayoutChooser, Bundle::Composite::Builder.
class Bundle
  module Composite
    module Layout
      module CountOverflow
        OUTPUT_WIDTH  = 300
        OUTPUT_HEIGHT = 400

        # Games section accent (Pale Cobalt) as [R, G, B].
        BG_COLOR  = [ 0x7e, 0xb6, 0xff ].freeze
        # Dracula background color as [R, G, B] — high contrast on Pale Cobalt.
        FG_COLOR  = [ 0x28, 0x2a, 0x36 ].freeze
        # Pango font string for libvips text renderer.
        FONT      = "Sans Bold".freeze
        # dpi → libvips text DPI
        TEXT_DPI  = 72

        # Cell positions as 0..1 ratios — see `Bundle::Composite::CellMap`.
        # Single full-canvas cell; no game tiles are composited.
        CELLS = [
          { x: 0.0, y: 0.0, w: 1.0, h: 1.0 }
        ].freeze

        module_function

        def layout_name
          "count_overflow"
        end

        def cells
          CELLS
        end

        # Compose a 300×400 solid-accent image with the count centered.
        #
        # @param tiles [Array] must be empty — no game images are used
        # @param total_member_count [Integer] the count to display (required)
        # @return [Vips::Image]
        def compose(tiles, total_member_count: nil)
          unless tiles.is_a?(Array) && tiles.empty?
            raise ArgumentError,
                  "CountOverflow expects an empty tiles array, got #{tiles.inspect}"
          end
          unless total_member_count.is_a?(Integer) && total_member_count >= 4
            raise ArgumentError,
                  "total_member_count must be an Integer >= 4 (got #{total_member_count.inspect})"
          end

          # Build solid background image: 300×400, sRGB, 8-bit.
          bg = Vips::Image.black(OUTPUT_WIDTH, OUTPUT_HEIGHT, bands: 3)
          bg = bg.linear(
            [ 1, 1, 1 ],
            BG_COLOR.map(&:to_f)
          )

          # Rasterize the count numeral. libvips `text` produces a 1-band
          # uint8 mask (white text on black). Font size is chosen so the
          # numeral height is ~55% of the canvas height (220px at 400 canvas).
          label    = total_member_count.to_s
          fontsize = font_size_for(label.length)

          text_mask = Vips::Image.text(
            label,
            font:  "#{FONT} #{fontsize}",
            dpi:   TEXT_DPI
          )

          # Convert 1-band mask to 3-band RGB in FG_COLOR.
          # `ifthenelse` picks FG pixel where mask is non-zero, else 0.
          fg_image = text_mask.ifthenelse(
            FG_COLOR,
            [ 0, 0, 0 ],
            blend: false
          )

          # Center the text on the canvas using composite2.
          text_w = fg_image.width
          text_h = fg_image.height
          left   = ((OUTPUT_WIDTH  - text_w) / 2.0).round
          top    = ((OUTPUT_HEIGHT - text_h) / 2.0).round

          # composite2 requires an alpha channel on the overlay.
          alpha   = text_mask.cast(:uchar)
          overlay = fg_image.bandjoin(alpha)

          bg.composite2(overlay, :over, x: left, y: top)
        end

        private

        # Returns a Pango font size (in points) that keeps the numeral
        # roughly 55% of the 400px canvas height regardless of digit count.
        # Single/double digit: 220px-equivalent. Triple digit: slightly
        # smaller to stay within the 300px width.
        def font_size_for(digit_count)
          case digit_count
          when 1, 2 then 140
          when 3    then 110
          else           90
          end
        end
      end
    end
  end
end
