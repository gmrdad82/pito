# frozen_string_literal: true

module Pito
  module Analytics
    module Visualizers
      # HEATMAP widget (owner brief 2026-07-01; generalized 2026-07-11): starts from
      # the no-data dotted canvas, then draws N EQUAL-WIDTH, FULL-HEIGHT braille
      # bars across the canvas. Value is encoded by COLOUR only (every bar is the
      # same size): each bar wears a solid tint sampled from the existing green→red
      # health ramp — the best column green, the worst red — via the per-bar
      # `--pito-heat` inline CSS var (0 = worst/red … 1 = best/green). The shared
      # pito-blue diagonal shimmer sweeps over the whole thing like the area chart.
      #
      # The day-of-week form is the PRESET: 7 values with no explicit `labels`
      # (Mon→Sun, from WeekdaySeries) wear the Mo…Su x-ticks and render exactly as
      # before — existing callers pass `values:` + `caption:` only and are
      # unchanged. Any other N brings its own `labels` (or none → no x-tick row).
      #
      # WIDTH IS THE LAW: the plot is always COLS cells wide — bars split that
      # fixed width (COLS / N cells each), they never grow it. N is therefore
      # capped at COLS (one braille cell is the minimum one-unit column) and a
      # heatmap needs at least 2 columns to compare; input outside 2..COLS — or
      # labels that don't pair 1:1 with values — is REFUSED and renders the
      # existing no-data treatment (the neutral all-0.5 weekday canvas), matching
      # the pre-generalization wrong-size fallback.
      #
      # Pure input: `values` (+ optional `labels`) and the pre-rendered `caption`.
      # Normalisation (min→max ⇒ 0→1) happens here so a re-render from the
      # persisted marker needs no refetch.
      class Heatmap < Pito::Analytics::Visualizers::Base
        REVEAL_CONTROLLER = "pito--area-chart-reveal"

        # Solid braille block (all 8 dots) — a bar is a full-ink rectangle the health
        # tint + shimmer clip to.
        BLOCK = [ 0x28FF ].pack("U")

        # Short weekday x-tick labels, Monday-first — the default preset: exactly
        # 7 values with `labels` omitted (parallel to `values`).
        DAY_LABELS = %w[Mo Tu We Th Fr Sa Su].freeze

        def reveal_controller = REVEAL_CONTROLLER

        # @param values  [Array<Numeric>] N per-column numbers (2..max_bars); the
        #   7-element form with no labels is the weekday preset (Mon..Sun)
        # @param caption [String] pre-rendered html-safe caption
        # @param labels  [Array<String>, nil] N x-tick labels paired 1:1 with
        #   `values`; nil defaults to DAY_LABELS when N == 7, else no x-tick row
        def initialize(values:, caption:, labels: nil)
          super(caption:)
          @values = Array(values).map(&:to_f)
          @labels = labels&.map(&:to_s)
          @labels = DAY_LABELS if @labels.nil? && @values.size == DAY_LABELS.size
          return if valid?

          # Refused input (see class doc) → the existing no-data treatment.
          @values = Array.new(DAY_LABELS.size, 0.0)
          @labels = DAY_LABELS
        end

        attr_reader :values, :labels

        # WIDTH IS THE LAW: the widest heatmap is one bar per braille cell, so the
        # bar-count cap derives straight from the canvas — COLS cells / a 1-cell
        # minimum column. No new width constant.
        def max_bars = cols

        # Total braille width of the plot (all bars), in cells — the span the
        # shimmer sweep is painted over so it reads as ONE continuous diagonal
        # across every bar (mirrors the area chart's full-height sweep).
        def plot_cols = cols

        # Per-bar cells: even split of COLS across the N bars (remainder spread to
        # the leftmost bars so the row still spans the full canvas width).
        def bar_cols
          n = @values.size
          base = cols / n
          extra = cols % n
          Array.new(n) { |i| base + (i < extra ? 1 : 0) }
        end

        # One bar per column: the full-height braille block string (rows joined by
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

        # Normalise a column value to 0..1 across the set's min..max (worst→best).
        # A flat set (all equal, incl. all-zero) maps to 0.5 — neutral, no false
        # winner/loser.
        def heat_fraction(value)
          lo = @values.min
          hi = @values.max
          return 0.5 if hi <= lo

          ((value - lo) / (hi - lo)).round(3)
        end

        # Grid tracks for the x-tick row when the bar count departs from the
        # 7-weekday preset (whose `repeat(7, 1fr)` lives in the stylesheet): one
        # fr per bar, PROPORTIONAL to its cell width, so each label centres under
        # ITS bar even when the remainder makes bars unequal. nil for the preset
        # count — the template then emits no style override and the preset render
        # stays byte-identical to the pre-generalization markup.
        def xtick_tracks
          return if @labels.nil? || @labels.size == DAY_LABELS.size

          bar_cols.map { |w| "#{w}fr" }.join(" ")
        end

        # Shimmer stagger seeded per data so side-by-side charts never sync.
        def shimmer_offset_class
          Pito::Shimmer.offset_class("heatmap-#{@values.join(',')}")
        end

        private

        # 2..max_bars values, and labels (when given) paired 1:1 with them.
        def valid?
          @values.size.between?(2, max_bars) &&
            (@labels.nil? || @labels.size == @values.size)
        end
      end
    end
  end
end
