# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # The bespoke VIEWS metric widget: a filled braille area chart of the daily
      # Views series over the period, in a ~thumbnail-wide 16:9 box, wearing a
      # subscriber-aware red→green health gradient (theme-token colours) with the
      # shared pito-blue bar shimmer swept over it, discrete tick VALUES (no axis
      # lines/names), and a witty caption below. Extends BaseComponent (shared
      # chrome) and is driven by the `pito--views-reveal` controller (which extends
      # the base reveal engine with the "D" bottom→up wipe + glow choreography).
      #
      # Pure inputs (the builder computes + persists these, so re-render needs no
      # refetch): the daily `series`, the `target_daily` green anchor, and the
      # pre-rendered `caption` (sampled no-repeat per message).
      class ViewsComponent < BaseComponent
        REVEAL_CONTROLLER = "pito--views-reveal"

        def reveal_controller = REVEAL_CONTROLLER

        def initialize(series:, target_daily:, caption:)
          super(caption:)
          @series       = Array(series).map(&:to_i)
          @target_daily = target_daily.to_f
        end

        # y-axis ceiling: the higher of the peak and the green target, so the
        # green line is always on-screen (and ≥1 to avoid an empty divisor).
        def ceiling
          [ @series.max.to_i, @target_daily.ceil, 1 ].max
        end

        # The braille area as one string per CELL row (top→bottom). The template
        # renders each as its own `.pito-metric__row` span so the reveal can wipe
        # them in bottom→up and each can carry the per-row gradient slice.
        def rows_braille
          Pito::Analytics::BrailleAreaChart.call(series: @series, cols:, rows:, max: ceiling)
        end

        # Discrete y-VALUES (no axis line): ~3 ticks (top / ~66% / ~33% of the
        # ceiling) placed at their data height (top%), compact-formatted.
        def y_ticks
          c = ceiling
          [ c, (c * 0.66).round, (c * 0.33).round ].map do |v|
            { label: fmt(v), top: ((1 - (v.to_f / c)) * 100).round(1) }
          end
        end

        # Discrete x-VALUES (below the plot): ~5 day positions spread across the
        # series, 1-based (compact-formatted day numbers).
        def x_ticks
          n = @series.size
          return [ "1" ] if n <= 1

          [ 0, 0.25, 0.5, 0.75, 1 ].map { |f| ((n - 1) * f).round + 1 }.uniq.map { |d| d.to_s }
        end

        # Where full-green sits within the y-range (0..100) — the data-driven
        # gradient stop, passed as the `--pito-green-anchor` CSS var.
        def green_anchor_pct
          (Pito::Analytics::Thresholds.green_anchor_fraction(target: @target_daily, ceiling:) * 100).round
        end

        # Shared staggered shimmer-delay bucket, SEEDED PER CHART (by the series),
        # so side-by-side Views charts never pulse in sync. Reuses the app's
        # `.pito-shimmer-dN` delay classes — applied to every row so the whole
        # chart shimmers as one diagonal at its own phase.
        def shimmer_offset_class
          Pito::Shimmer.offset_class(@series.join(","), seed: @target_daily)
        end

        private

        # Compact number for ticks: 12_300 → "12K", 842_000 → "842K".
        def fmt(value)
          v = value.to_i
          return v.to_s if v < 1000

          k = v / 1000.0
          str = k >= 10 ? k.round.to_s : k.round(1).to_s.sub(/\.0$/, "")
          "#{str}K"
        end
      end
    end
  end
end
