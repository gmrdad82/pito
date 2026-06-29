# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # One analytics metric as a label + value pair (the kv cell) — used by the
      # show vid/game `:enhanced` glance AND the `analyze` `0`/`1` scaffold.
      #
      # `value` is pre-rendered, html-safe content (a TrendNumberComponent render, a
      # split "+gained/-lost" / "👍/👎" value, or a plain "1"/"0").
      #
      # When a `series:` is supplied (glance day-series), a dedicated
      # Metric::SparklineComponent renders ABOVE the pair — the sparkline is its OWN
      # component, NOT inline chart code here. No series → just the label/value pair.
      class CompactComponent < ViewComponent::Base
        # @param label      [String] metric label
        # @param value      [String] pre-rendered html-safe value
        # @param series     [Array<Numeric>] optional day-series → renders a sparkline
        # @param series_max [Numeric] optional sparkline y-axis ceiling
        def initialize(label:, value:, series: nil, series_max: nil)
          @label      = label
          @value      = value
          @series     = Array(series).map(&:to_f).presence
          @series_max = series_max
        end

        attr_reader :label, :value, :series, :series_max

        # True when a numeric series was supplied; gates the sparkline.
        def series? = @series.present?
      end
    end
  end
end
