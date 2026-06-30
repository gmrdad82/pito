# frozen_string_literal: true

module Pito
  module Analytics
    module Slots
      # One analytics metric cell — used by the show vid/game `:enhanced` glance
      # AND the `analyze` `0`/`1` scaffold.
      #
      # Composes:
      #   - `Pito::Analytics::Support::MetricName` for the label
      #   - A `:scalar` content slot (number / trend / ratio) passed by the caller
      #   - Optionally a `Visualizers::Sparkline` or `Visualizers::NoData` above
      #     the pair when a series is supplied or the cell is in a loading state.
      #
      # Three render branches:
      #   loading:            NoData(:compact) above pair; pair = MetricName + LoadingDots
      #   filled + series:    Sparkline above pair; pair = MetricName + scalar slot
      #   filled + no series: bare pair = MetricName + scalar slot (no canvas chrome)
      class Compact < ViewComponent::Base
        renders_one :scalar

        # @param name       [String]          metric display name (already localized)
        # @param series     [Array<Numeric>]  optional day-series → renders a sparkline
        # @param series_max [Numeric]         optional sparkline y-axis ceiling
        # @param loading    [Boolean]         true → renders the loading skeleton
        def initialize(name:, series: nil, series_max: nil, loading: false)
          @name       = name
          @series     = Array(series).map(&:to_f).presence
          @series_max = series_max
          @loading    = loading
        end

        attr_reader :name, :series, :series_max

        def loading? = @loading
        def series?  = @series.present?
      end
    end
  end
end
