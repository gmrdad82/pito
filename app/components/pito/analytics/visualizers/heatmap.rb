# frozen_string_literal: true

module Pito
  module Analytics
    module Visualizers
      # Day-of-week HEATMAP widget (owner brief 2026-07-01): starts from the no-data
      # dotted canvas, then draws 7 EQUAL-WIDTH, FULL-HEIGHT braille bars — one per
      # weekday (Mon→Sun) — across the canvas. Value is encoded by COLOUR only (every
      # bar is the same size): each bar wears a solid tint sampled from the existing
      # green→red health ramp — the busiest weekday green, the quietest red — via the
      # per-bar `--pito-heat` inline CSS var (0 = worst/red … 1 = best/green). The
      # shared pito-blue diagonal shimmer sweeps over the whole thing like the area
      # chart. x-axis ticks read Mo Tu We Th Fr Sa Su.
      #
      # Pure input: `values` — 7 avg-views floats (Mon..Sun, from WeekdaySeries) — and
      # the pre-rendered `caption`. Normalisation (min→max ⇒ 0→1) happens here so a
      # re-render from the persisted marker needs no refetch.
      class Heatmap < Pito::Analytics::Visualizers::Base
        REVEAL_CONTROLLER = "pito--area-chart-reveal"

        # Solid braille block (all 8 dots) — a bar is a full-ink rectangle the health
        # tint + shimmer clip to.
        BLOCK = [ 0x28FF ].pack("U")

        # Short weekday x-tick labels, Monday-first (parallel to `values`).
        DAY_LABELS = %w[Mo Tu We Th Fr Sa Su].freeze

        def reveal_controller = REVEAL_CONTROLLER

        # @param values  [Array<Numeric>] 7 avg-views per weekday (Mon..Sun)
        # @param caption [String] pre-rendered html-safe caption
        def initialize(values:, caption:)
          super(caption:)
          @values = Array(values).map(&:to_f)
          @values = Array.new(7, 0.0) if @values.size != 7
        end

        attr_reader :values

        def day_labels = DAY_LABELS

        # Total braille width of the plot (all 7 bars), in cells — the span the
        # shimmer sweep is painted over so it reads as ONE continuous diagonal
        # across every weekday (mirrors the area chart's full-height sweep).
        def plot_cols = cols

        # Per-bar cells: even split of COLS across the 7 bars (remainder spread to the
        # leftmost bars so the row still spans the full canvas width).
        def bar_cols
          base = cols / 7
          extra = cols % 7
          Array.new(7) { |i| base + (i < extra ? 1 : 0) }
        end

        # One bar per weekday: the full-height braille block string (rows joined by
        # newline; `white-space: pre` renders the stack), its heat fraction, and its
        # LEFT offset in cells (cumulative width of the prior bars) so the shared
        # shimmer band can be positioned to flow continuously across all bars.
        def bars
          widths = bar_cols
          offset = 0
          @values.each_with_index.map do |value, i|
            glyphs = Array.new(rows) { BLOCK * widths[i] }.join("\n")
            bar = { glyphs:, heat: heat_fraction(value), offset: }
            offset += widths[i]
            bar
          end
        end

        # Normalise a weekday value to 0..1 across the week's min..max (worst→best).
        # A flat week (all equal, incl. all-zero) maps to 0.5 — neutral, no false
        # winner/loser.
        def heat_fraction(value)
          lo = @values.min
          hi = @values.max
          return 0.5 if hi <= lo

          ((value - lo) / (hi - lo)).round(3)
        end

        # Shimmer stagger seeded per data so side-by-side charts never sync.
        def shimmer_offset_class
          Pito::Shimmer.offset_class("heatmap-#{@values.join(',')}")
        end
      end
    end
  end
end
