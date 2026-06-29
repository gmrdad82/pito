# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # Reusable area-chart widget for `:system` metrics (views, watched_hours,
      # subs). Renders a filled braille area chart of the metric's daily series
      # over the period, in a ~thumbnail-wide 16:9 box, wearing a
      # subscriber-aware red→green health gradient (theme-token colours) with the
      # shared pito-blue bar shimmer swept over it, discrete tick VALUES (no axis
      # lines/names), and a witty caption below. Extends BaseComponent (shared
      # chrome) and is driven by the `pito--area-chart-reveal` controller (which
      # extends the base reveal engine with the "D" bottom→up wipe + glow
      # choreography).
      #
      # Pure inputs (the builder computes + persists these, so re-render needs no
      # refetch): the `metric` (symbol), the daily `series`, the `target_daily`
      # green anchor, and the pre-rendered `caption` (sampled no-repeat per message).
      #
      # Shimmer offset is seeded per (metric, series) so two charts showing the
      # same data for different metrics still pulse at different phases — even if
      # their series values happen to be identical.
      #
      # `trend: false` records that this chart carries no trend triangle (the
      # triangle is baked into the pre-rendered caption by the builder). Used by
      # the scaffold template and inspectable in specs.
      #
      # `reference_token:` records an override for the caption's cyan reference
      # (e.g. "lifetime" for avg_viewed_pct). Also baked into the caption by the
      # builder; stored here for traceability.
      class AreaChartComponent < BaseComponent
        REVEAL_CONTROLLER = "pito--area-chart-reveal"

        def reveal_controller = REVEAL_CONTROLLER

        # `dates` is an optional array of ISO-8601 strings (or Date objects) —
        # one per data point — used to label x-axis ticks with real dates.
        # Omitting it falls back to the old day-index labels ("1", "8", …).
        def initialize(metric:, series:, target_daily:, caption:, trend: true, reference_token: nil, dates: nil)
          super(caption:)
          @metric          = metric.to_sym
          @series          = Array(series).map(&:to_f)
          @target_daily    = target_daily.to_f
          @trend           = trend
          @reference_token = reference_token
          @dates           = parse_dates(dates)
        end

        attr_reader :trend, :reference_token

        # y-axis ceiling: the higher of the peak and the green target, so the
        # green line is always on-screen (and ≥1 to avoid an empty divisor).
        def ceiling
          [ @series.max.to_f, @target_daily, 1.0 ].max
        end

        # The braille area as one string per CELL row (top→bottom). The template
        # renders each as its own `.pito-metric__row` span so the reveal can wipe
        # them in bottom→up and each can carry the per-row gradient slice.
        def rows_braille
          # BrailleAreaChart expects integer-valued series; convert by rounding.
          int_series = @series.map(&:round)
          Pito::Analytics::BrailleAreaChart.call(series: int_series, cols:, rows:, max: ceiling.ceil)
        end

        # Discrete y-VALUES (no axis line): ~3 ticks (top / ~66% / ~33% of the
        # ceiling) placed at their data height (top%), compact-formatted.
        def y_ticks
          c = ceiling
          [ c, (c * 0.66), (c * 0.33) ].map do |v|
            { label: fmt(v), top: ((1 - (v / c)) * 100).round(1) }
          end
        end

        # Discrete x-VALUES (below the plot). For the retention curve
        # (:avg_viewed_pct) the x-axis is the video position (0%→100%) rather
        # than dates. For all other metrics: when `dates:` are present, label
        # ~5 evenly-spaced ticks with adaptive date strings (current year →
        # "24 Feb"; prior year → "June 2025"). Falls back to day-index when no
        # dates are provided (backward-compat for persisted markers without dates).
        def x_ticks
          return [ "0%", "25%", "50%", "75%", "100%" ] if @metric == :avg_viewed_pct

          if @dates.present?
            n = @dates.size
            return [ format_date(@dates.first) ] if n <= 1

            [ 0, 0.25, 0.5, 0.75, 1 ].map { |f| ((n - 1) * f).round }.uniq.map { |i| format_date(@dates[i]) }
          else
            n = @series.size
            return [ "1" ] if n <= 1

            [ 0, 0.25, 0.5, 0.75, 1 ].map { |f| ((n - 1) * f).round + 1 }.uniq.map { |d| d.to_s }
          end
        end

        # Where full-green sits within the y-range (0..100) — the data-driven
        # gradient stop, passed as the `--pito-green-anchor` CSS var.
        def green_anchor_pct
          (Pito::Analytics::Thresholds.green_anchor_fraction(target: @target_daily, ceiling:) * 100).round
        end

        # Shared staggered shimmer-delay bucket, SEEDED PER (metric, series) so
        # side-by-side area charts never pulse in sync — even when the series
        # values happen to be identical across metrics. Reuses the app's
        # `.pito-shimmer-dN` delay classes — applied to every row so the whole
        # chart shimmers as one diagonal at its own phase.
        def shimmer_offset_class
          Pito::Shimmer.offset_class("#{@metric}-#{@series.join(',')}", seed: @target_daily)
        end

        private

        # Parse an array of ISO-8601 strings or Date objects into Date instances.
        # Invalid entries are silently dropped.
        def parse_dates(dates)
          return [] if dates.blank?

          Array(dates).filter_map do |d|
            next d if d.is_a?(Date)

            Date.parse(d.to_s)
          rescue ArgumentError, TypeError
            nil
          end
        end

        # Format a Date for an x-axis tick:
        #   current year → "24 Feb"  (day of month + abbreviated month)
        #   prior year   → "June 2025" (full month + year)
        def format_date(date)
          if date.year == Date.current.year
            date.strftime("%-d %b")
          else
            date.strftime("%B %Y")
          end
        end

        # Compact tick label, metric-aware:
        #   :avg_view_duration → M:SS (e.g. "2:05")
        #   :avg_viewed_pct    → "XX.X%" (e.g. "45.2%")
        #   others             → compact count (12_300 → "12K")
        def fmt(value)
          case @metric
          when :avg_view_duration
            Pito::Formatter::Duration.call(value.to_f) || "0:00"
          when :avg_viewed_pct
            format("%.2f%%", value.to_f)
          else
            compact_count(value)
          end
        end

        # Compact number for numeric metrics: 12_300 → "12K", 842_000 → "842K".
        # For sub-1000 floats (e.g. watched hours), shows one decimal only when
        # the value is not a whole number and is small (< 10).
        def compact_count(value)
          v = value.to_f
          n = v.round
          return n.to_s if n < 1000

          k = n / 1000.0
          str = k >= 10 ? k.round.to_s : k.round(1).to_s.sub(/\.0$/, "")
          "#{str}K"
        end
      end
    end
  end
end
