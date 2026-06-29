# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # Dedicated 2-row braille SPARKLINE — the mini area-chart shown above a glance
      # scalar (Metric::CompactComponent). A first-class, reusable renderer (NOT
      # inline in the host template): flat fg-default base under the shared pito-blue
      # chart-viz shimmer (--pito-shimmer-angle) + bottom→up reveal, with NO
      # ticks/legend/caption/axis — just the 2 braille rows on the dotted-paper grid,
      # floored with a baseline row so an all-zero series still shows a minimal
      # x-axis line. Width = BaseComponent::COLS (45) = the analyze chart wrapper width.
      class SparklineComponent < BaseComponent
        ROWS = 2
        REVEAL_CONTROLLER = "pito--area-chart-reveal"

        # @param series     [Array<Numeric>] day-series to plot
        # @param series_max [Numeric] y-axis ceiling (≥ 1); defaults to the series peak
        def initialize(series:, series_max: nil)
          super(caption: "") # BaseComponent requires caption; unused here
          raw         = Array(series).map(&:to_f)
          @series     = raw.presence || [ 0.0 ]
          @series_max = [ (series_max || raw.max || 1).to_f, 1.0 ].max
        end

        def reveal_controller = REVEAL_CONTROLLER

        # ROWS (2) strings of COLS (45) chars each (top→bottom), capped at series_max.
        def rows_braille
          Pito::Analytics::BrailleAreaChart.call(series: @series.map(&:round), cols:, rows:, max: @series_max.ceil)
        end

        # Staggered shimmer-delay bucket, seeded per series so adjacent sparklines
        # never pulse in sync.
        def shimmer_offset_class
          Pito::Shimmer.offset_class("sparkline-#{@series.join(',')}", seed: @series_max)
        end
      end
    end
  end
end
