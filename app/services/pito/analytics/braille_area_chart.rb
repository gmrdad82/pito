# frozen_string_literal: true

module Pito
  module Analytics
    # Renders a numeric series as a filled-area chart drawn in Unicode BRAILLE.
    #
    # Each braille cell packs a 2×4 dot grid, so a `cols × rows` cell grid is a
    # `2·cols × 4·rows` dot canvas — high resolution in a tiny character box. The
    # area UNDER the curve is filled (dots set from the baseline up to each
    # column's height), which is what reads as a Studio-style area chart.
    #
    #   Pito::Analytics::BrailleAreaChart.call(series: [1, 4, 2, 9], cols: 44, rows: 11)
    #   # => ["⠀⠀…", …]   (rows top→bottom; each a `cols`-char braille string)
    #
    # The caller owns axes + colour (gradient). This service is PURE: series in,
    # braille rows out. `max` fixes the y-axis ceiling (e.g. max(peak, target) so a
    # health threshold is always on-screen); it defaults to the series peak.
    module BrailleAreaChart
      BLANK = 0x2800 # U+2800 — the empty braille cell (keeps monospacing)

      # Baseline floor: every column draws at LEAST this many dots from the
      # bottom, so empty / zero values read as a minimal baseline (a continuous
      # area chart) rather than blank gaps. 0 and "no data" both render the floor.
      BASELINE_DOTS = 1

      # Unicode braille dot bit by [local_col (0=left,1=right)][local_row 0..3 top→bottom].
      #   left col  = dots 1,2,3,7   right col = dots 4,5,6,8
      DOT = [
        [ 0x01, 0x02, 0x04, 0x40 ],
        [ 0x08, 0x10, 0x20, 0x80 ]
      ].freeze

      module_function

      # @param series [Array<Numeric>] the values, left→right
      # @param cols   [Integer] braille CELL columns (width)  → 2·cols dot columns
      # @param rows   [Integer] braille CELL rows (height)     → 4·rows dot rows
      # @param max    [Numeric, nil] y-axis ceiling; defaults to the series peak
      # @return [Array<String>] `rows` braille strings, top→bottom, each `cols` wide
      def call(series:, cols:, rows:, max: nil)
        cols = [ cols.to_i, 1 ].max
        rows = [ rows.to_i, 1 ].max
        dot_w = cols * 2
        dot_h = rows * 4

        values = Array(series).map(&:to_f)
        ceiling = (max || values.max || 0).to_f

        heights = column_heights(values, ceiling, dot_w, dot_h)
        pack(heights, cols, rows, dot_h)
      end

      # Filled dot-height (BASELINE_DOTS..dot_h) for each of the dot_w columns.
      # Empty / all-zero → a flat baseline; otherwise each value is floored to the
      # baseline so 0-days still show the minimal dot row. Any strictly-positive
      # value is guaranteed at least one dot above the baseline floor so a tiny
      # entry (e.g. 1 view against a high max) is visually distinct from zero.
      def column_heights(values, ceiling, dot_w, dot_h)
        floor = [ BASELINE_DOTS, dot_h ].min
        return Array.new(dot_w, floor) if ceiling <= 0 || values.empty?

        Array.new(dot_w) do |x|
          v = sample(values, x, dot_w)
          h = [ ((v / ceiling) * dot_h).round.clamp(0, dot_h), floor ].max
          # Ensure every strictly-positive value renders at least one braille
          # level above the baseline so it is never confused with a genuine zero.
          h = [ floor + 1, dot_h ].min if v.positive? && h <= floor
          h
        end
      end

      # Linear-interpolated value at dot-column x (stretches/compresses the series
      # to the canvas width). Single-point series → flat.
      def sample(values, x, dot_w)
        return values.first if values.size == 1

        pos  = dot_w == 1 ? 0.0 : x * (values.size - 1) / (dot_w - 1).to_f
        lo   = pos.floor
        hi   = pos.ceil
        return values[lo] if lo == hi

        values[lo] * (1 - (pos - lo)) + values[hi] * (pos - lo)
      end

      # Pack the per-column heights into braille cell rows (top→bottom). A dot at
      # (x, y) is set when y is within the column's bottom-anchored fill.
      def pack(heights, cols, rows, dot_h)
        Array.new(rows) do |cell_row|
          (0...cols).map do |cell_col|
            mask = 0
            2.times do |lc|
              h = heights[(cell_col * 2) + lc] || 0
              next unless h.positive?

              4.times do |lr|
                y = (cell_row * 4) + lr
                mask |= DOT[lc][lr] if y >= dot_h - h
              end
            end
            (BLANK + mask).chr(Encoding::UTF_8)
          end.join
        end
      end
    end
  end
end
