# frozen_string_literal: true

module Pito
  module Analytics
    # Renders a HEART in braille, filled bottom→top to a 0..100 score — the likes
    # metric's analogue of BrailleAreaChart. Color-agnostic: returns, per braille
    # CELL, the glyph + a `state` (:filled / :outline / :interior / :outside) so
    # the COMPONENT applies colors + the chosen empty-treatment.
    #
    # Each braille cell packs a 2×4 DOT grid, so a `cols × rows` CELL grid is a
    # `2·cols × 4·rows` DOT canvas — enough vertical resolution that a COMPACT
    # ~4-cell-row heart still shows the lobe CLEFT + the bottom CUSP (which a
    # one-glyph-per-cell renderer cannot). The shape is the classic implicit curve
    #   (x² + y² − 1)³ − x²·y³ ≤ 0
    # sampled per dot. Fill is a horizontal waterline: the bottom `score%` of the
    # canvas height is :filled.
    #
    #   Pito::Analytics::BrailleHeart.call(score: 92, cols: 13, rows: 4)
    #   # => [[{char: "⣿", state: :filled}, …], …]  (rows top→bottom)
    #
    # The four states let the component pick an empty-treatment: OUTLINE (color
    # :outline, blank :interior → hollow) or FADED (dim :outline + :interior →
    # solid silhouette behind the colored fill).
    module BrailleHeart
      # Default CELL dims — COMPACT (~4 char-rows) so the heart sits at the area
      # chart's visible fill height, not towering over it.
      DEFAULT_COLS = 13
      DEFAULT_ROWS = 4

      # The heart is inset from the canvas edges: a TOP margin moves it DOWN (off
      # the top edge) and a BOTTOM margin lifts the cusp off the floor. The empty
      # margin rows show the dotted-paper background behind.
      TOP_MARGIN_ROWS    = 1
      BOTTOM_MARGIN_ROWS = 1

      # Unicode braille dot bits by [local_row 0..3 top→bottom][local_col 0..1].
      BITS  = [ [ 0x01, 0x08 ], [ 0x02, 0x10 ], [ 0x04, 0x20 ], [ 0x40, 0x80 ] ].freeze
      BLANK = 0x2800

      module_function

      # @param score [Numeric] 0..100 fill level (clamped)
      # @param cols  [Integer] braille CELL columns (heart width)
      # @param rows  [Integer] braille CELL rows (heart height)
      # @return [Array<Array<Hash>>] `rows` rows top→bottom, each `cols` cells
      #   `{ char: String, state: Symbol }`.
      def call(score:, cols: DEFAULT_COLS, rows: DEFAULT_ROWS, top_margin_rows: TOP_MARGIN_ROWS, bottom_margin_rows: BOTTOM_MARGIN_ROWS)
        cols = [ cols.to_i, 2 ].max
        rows = [ rows.to_i, 4 ].max
        pct  = score.to_f.clamp(0.0, 100.0)

        dot_w = cols * 2
        dot_h = rows * 4
        # The heart occupies a SUB-region of the canvas — a TOP margin (so it sits
        # lower, not hugging the top edge) down to a BOTTOM margin above the floor.
        heart_top    = top_margin_rows.to_i * 4
        heart_bottom = dot_h - (bottom_margin_rows.to_i * 4)
        heart_h      = heart_bottom - heart_top
        mask = heart_mask(dot_w, dot_h, heart_top, heart_h)
        # Fill is HEART-RELATIVE (no axis): 0% = the CUSP (bottom tip), 100% = the
        # LOBE TOPS. The waterline sweeps the heart's OWN vertical extent, not the
        # canvas — so margins above/below never count toward the fill.
        waterline = heart_bottom - (pct / 100.0) * heart_h

        Array.new(rows) do |cr|
          Array.new(cols) do |cc|
            cell(mask, cr, cc, waterline)
          end
        end
      end

      # Boolean dot mask of the heart over a dot_w × dot_h canvas. The coord space
      # spans the FULL heart: x∈[-1.3,1.3]; y from ≈1.26 (lobe tops, where x=0 is
      # OUTSIDE → the cleft) down to ≈-1.16 (the cusp).
      # Boolean dot mask over the FULL dot_w × dot_h canvas, but the heart shape is
      # confined to the region [heart_top, heart_top+heart_h): rows outside it are
      # forced blank (the margins). Within the region the shape spans its full
      # range (lobe tops at heart_top, cusp at heart_top+heart_h).
      def heart_mask(dot_w, dot_h, heart_top, heart_h)
        Array.new(dot_h) do |dy|
          Array.new(dot_w) do |dx|
            next false if dy < heart_top || dy >= heart_top + heart_h

            x = ((dx + 0.5) - dot_w / 2.0) / (dot_w / 2.0) * 1.28
            # y_top ≈ 1.15 lands ON the lobe peaks (lobe-tops at the region top,
            # cleft between them); y_bottom ≈ -1.05 puts the cusp at the region
            # bottom — the heart fills its inset region.
            y = 1.15 - (dy + 0.5 - heart_top) / heart_h * 2.2
            a = (x * x) + (y * y) - 1.0
            (a * a * a) - (x * x * (y * y * y)) <= 0.0
          end
        end
      end

      # One braille cell: glyph (from its in-heart dots) + state vs the waterline.
      def cell(mask, cell_row, cell_col, fill_top)
        base_r = cell_row * 4
        base_c = cell_col * 2

        bits = 0
        in_heart = 0
        filled_dots = 0
        (0..3).each do |lr|
          (0..1).each do |lc|
            next unless mask.dig(base_r + lr, base_c + lc)

            bits |= BITS[lr][lc]
            in_heart += 1
            filled_dots += 1 if (base_r + lr) >= fill_top
          end
        end

        return { char: [ BLANK ].pack("U"), state: :outside } if in_heart.zero?

        char = [ BLANK | bits ].pack("U")
        return { char:, state: :filled } if filled_dots.positive? # at/below waterline

        state = boundary_cell?(mask, base_r, base_c) ? :outline : :interior
        { char:, state: }
      end

      # A cell is on the heart BOUNDARY when one of its in-heart dots has a
      # 4-neighbour off-heart (or off-canvas) — used to draw the hollow outline.
      def boundary_cell?(mask, base_r, base_c)
        (0..3).each do |lr|
          (0..1).each do |lc|
            r = base_r + lr
            c = base_c + lc
            next unless mask.dig(r, c)

            return true if [ [ r - 1, c ], [ r + 1, c ], [ r, c - 1 ], [ r, c + 1 ] ].any? do |nr, nc|
              nr.negative? || nc.negative? || !mask.dig(nr, nc)
            end
          end
        end
        false
      end
    end
  end
end
