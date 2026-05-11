# Phase 27 §01h — Pure layout engine for Collection composite covers.
#
# Stitches up to 6 IGDB cover tiles into a single shelf-sized image
# (output canvas matches `Games::CoverComponent::DIMENSIONS[:shelf]` —
# locked at 98 × 130 per the open-question fallback path in the spec).
# Layout selection is keyed on tile count (0 / 1 / 2 / 3 / 4 / 5 / 6+).
#
# Variant matrix (pixel boxes are derived in `tile_boxes` and verified
# by the spec — each row sums to OUTPUT_WIDTH, each column to
# OUTPUT_HEIGHT, no gaps, no overlaps):
#
#   :empty       → 0 tiles. Caller renders an `[empty]` placeholder; no
#                  composite is produced.
#   :passthrough → 1 tile.  Caller renders a `Games::CoverComponent`
#                  directly; no composite is produced.
#   :pair        → 2 tiles. 1 × 2 side-by-side.  49×130 / 49×130.
#   :netflix3    → 3 tiles. Big left + 2 small stacked right.
#                  big 64×130; top-right 34×65; bottom-right 34×65.
#   :quad        → 4 tiles. 2 × 2 grid.
#                  TL 49×65, TR 49×65, BL 49×65, BR 49×65.
#   :netflix5    → 5 tiles. Big left + 2 × 2 grid right.
#                  big 50×130; TR 24×65, TR2 24×65 (top row);
#                  BR 24×65, BR2 24×65 (bottom row).
#   :six_grid    → 6+ tiles (only first 6 contribute).
#                  3 × 2 grid; each row 33+33+32 = 98; rows 65 each.
#
# Pure module — knows nothing about Collections, the tile cache,
# fingerprints, or filenames. The `compose` method takes an array of
# `Vips::Image | nil` tiles; `nil` slots are substituted with a flat
# dark-grey placeholder block matching `Composite::Layout::NineGrid::
# BG_RGB = [30, 30, 30]`.
module Collections
  module CompositeLayout
    OUTPUT_WIDTH  = 98
    OUTPUT_HEIGHT = 130
    BG_RGB = [ 30, 30, 30 ].freeze

    LAYOUTS = %i[empty passthrough pair netflix3 quad netflix5 six_grid].freeze

    module_function

    # Return the layout symbol for a given member count.
    #
    #   choose(0)    → :empty
    #   choose(1)    → :passthrough
    #   choose(2)    → :pair
    #   choose(3)    → :netflix3
    #   choose(4)    → :quad
    #   choose(5)    → :netflix5
    #   choose(6..)  → :six_grid
    #   choose(-1)   → ArgumentError
    #   choose("3")  → ArgumentError
    def choose(count)
      raise ArgumentError, "count must be an integer" unless count.is_a?(Integer)
      raise ArgumentError, "count must be non-negative (got #{count})" if count.negative?

      case count
      when 0 then :empty
      when 1 then :passthrough
      when 2 then :pair
      when 3 then :netflix3
      when 4 then :quad
      when 5 then :netflix5
      else        :six_grid
      end
    end

    # Return the array of `{ x:, y:, w:, h: }` slot boxes for the given
    # layout against an output canvas of `output_w` × `output_h`. The
    # default canvas matches the `:shelf` cover-art variant.
    #
    # Pixel math is computed analytically so the boxes scale
    # proportionally for non-default canvases (useful if `:shelf` ever
    # changes — the spec pins this behavior). Returns [] for `:empty`
    # and `:passthrough` (those layouts do NOT produce a composite).
    def tile_boxes(layout, output_w: OUTPUT_WIDTH, output_h: OUTPUT_HEIGHT)
      validate_layout!(layout)
      case layout
      when :empty, :passthrough then []
      when :pair                then pair_boxes(output_w, output_h)
      when :netflix3            then netflix3_boxes(output_w, output_h)
      when :quad                then quad_boxes(output_w, output_h)
      when :netflix5            then netflix5_boxes(output_w, output_h)
      when :six_grid            then six_grid_boxes(output_w, output_h)
      end
    end

    # Compose the tiles into a single `Vips::Image` of OUTPUT_WIDTH ×
    # OUTPUT_HEIGHT. `tiles` is an Array<Vips::Image | nil>; nil entries
    # are substituted with the placeholder block at the matching slot's
    # exact dimensions. Tile count MUST equal `tile_boxes(layout).size`.
    #
    # Raises `ArgumentError` for `:empty` and `:passthrough` (the caller
    # is expected to short-circuit those layouts before calling compose).
    def compose(layout, tiles)
      validate_layout!(layout)
      if %i[empty passthrough].include?(layout)
        raise ArgumentError, "layout #{layout.inspect} does not compose"
      end

      boxes = tile_boxes(layout)
      unless tiles.size == boxes.size
        raise ArgumentError,
              "expected #{boxes.size} tiles for layout #{layout.inspect}, got #{tiles.size}"
      end

      sized = boxes.zip(tiles).map { |box, tile| size_tile(tile, box[:w], box[:h]) }
      case layout
      when :pair     then compose_pair(sized)
      when :netflix3 then compose_netflix3(sized)
      when :quad     then compose_quad(sized)
      when :netflix5 then compose_netflix5(sized)
      when :six_grid then compose_six_grid(sized)
      end
    end

    # Build the placeholder block at the given dimensions. Public so the
    # composer service can substitute a placeholder for a tile-fetch
    # error in the SAME shape `compose` would have used for a `nil`
    # slot. Matches `Composite::Layout::NineGrid::BG_RGB`.
    def placeholder_tile(w, h)
      Vips::Image.black(w, h).new_from_image(BG_RGB)
    end

    class << self
      private

      def validate_layout!(layout)
        return if LAYOUTS.include?(layout)
        raise ArgumentError, "unknown layout #{layout.inspect}"
      end

      # --- Per-variant box derivations --------------------------------
      #
      # Each derivation is exact integer arithmetic against the input
      # canvas dimensions. Sums verify to (w, h) for all six layouts at
      # the canonical 98 × 130 shelf size and at the alternate 105 × 140
      # reference size in the spec.

      def pair_boxes(w, h)
        left_w  = w / 2
        right_w = w - left_w
        [
          { x: 0,      y: 0, w: left_w,  h: h },
          { x: left_w, y: 0, w: right_w, h: h }
        ]
      end

      def netflix3_boxes(w, h)
        # Big left ≈ 2/3 width (integer floor on the doubled half).
        # For 98 → big 64, right 34. For 105 → big 70, right 35.
        big_w   = (w / 3) * 2
        right_w = w - big_w
        top_h   = h / 2
        bot_h   = h - top_h
        [
          { x: 0,     y: 0,     w: big_w,   h: h },
          { x: big_w, y: 0,     w: right_w, h: top_h },
          { x: big_w, y: top_h, w: right_w, h: bot_h }
        ]
      end

      def quad_boxes(w, h)
        left_w  = w / 2
        right_w = w - left_w
        top_h   = h / 2
        bot_h   = h - top_h
        [
          { x: 0,      y: 0,     w: left_w,  h: top_h },
          { x: left_w, y: 0,     w: right_w, h: top_h },
          { x: 0,      y: top_h, w: left_w,  h: bot_h },
          { x: left_w, y: top_h, w: right_w, h: bot_h }
        ]
      end

      def netflix5_boxes(w, h)
        # Big left + a 2×2 right column. Right column width is the
        # largest even number ≤ half the canvas so each right cell is an
        # integer width.
        right_w = ((w / 2) / 2) * 2  # 98 → 48; 105 → 52.
        big_w   = w - right_w
        cell_w  = right_w / 2
        top_h   = h / 2
        bot_h   = h - top_h
        [
          { x: 0,              y: 0,     w: big_w,  h: h     },
          { x: big_w,          y: 0,     w: cell_w, h: top_h },
          { x: big_w + cell_w, y: 0,     w: cell_w, h: top_h },
          { x: big_w,          y: top_h, w: cell_w, h: bot_h },
          { x: big_w + cell_w, y: top_h, w: cell_w, h: bot_h }
        ]
      end

      def six_grid_boxes(w, h)
        # 3 cols × 2 rows. Distribute extra width starting from the
        # leftmost column when `w` is not divisible by 3. For 98:
        # 33 + 33 + 32 = 98 (leftmost two columns carry +1 pixel).
        base_col   = w / 3
        extra      = w - base_col * 3
        col_widths = Array.new(3, base_col)
        extra.times { |i| col_widths[i] += 1 }

        top_h = h / 2
        bot_h = h - top_h

        boxes = []
        [ [ 0, top_h ], [ top_h, bot_h ] ].each do |(y_origin, row_h)|
          x = 0
          col_widths.each do |cw|
            boxes << { x: x, y: y_origin, w: cw, h: row_h }
            x += cw
          end
        end
        boxes
      end

      # --- Tile sizing and composition --------------------------------

      # Resize `tile` to `(w, h)`. nil tiles → placeholder block.
      def size_tile(tile, w, h)
        if tile.nil?
          placeholder_tile(w, h)
        else
          tile.thumbnail_image(w, height: h, crop: :centre)
        end
      end

      def compose_pair(tiles)
        tiles[0].join(tiles[1], :horizontal)
      end

      def compose_netflix3(tiles)
        big       = tiles[0]
        right_top = tiles[1]
        right_bot = tiles[2]
        right_col = right_top.join(right_bot, :vertical)
        big.join(right_col, :horizontal)
      end

      def compose_quad(tiles)
        top_row = tiles[0].join(tiles[1], :horizontal)
        bot_row = tiles[2].join(tiles[3], :horizontal)
        top_row.join(bot_row, :vertical)
      end

      def compose_netflix5(tiles)
        big       = tiles[0]
        top_row   = tiles[1].join(tiles[2], :horizontal)
        bot_row   = tiles[3].join(tiles[4], :horizontal)
        right_col = top_row.join(bot_row, :vertical)
        big.join(right_col, :horizontal)
      end

      def compose_six_grid(tiles)
        top_row = tiles[0].join(tiles[1], :horizontal).join(tiles[2], :horizontal)
        bot_row = tiles[3].join(tiles[4], :horizontal).join(tiles[5], :horizontal)
        top_row.join(bot_row, :vertical)
      end
    end
  end
end
