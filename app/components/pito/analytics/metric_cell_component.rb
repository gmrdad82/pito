# frozen_string_literal: true

module Pito
  module Analytics
    # One glance metric cell — the `<token>__metric_<key>` swap target. The single
    # source of truth for a cell's chrome + dom-id so the loading skeleton
    # (ScalarsTableComponent), the live per-metric swap (AnalyticsMetricJob), and
    # the persisted ready render all emit an IDENTICAL element. Delegates the inner
    # cell to Slots::Compact (loading skeleton, or filled sparkline + scalar).
    class MetricCellComponent < ViewComponent::Base
      # @param key     [Symbol, String] metric key → dom-id `<token>__metric_<key>`
      # @param label   [String]         localized metric name
      # @param token   [String, nil]    per-message token for the stable dom-id
      # @param series  [Array, nil]     day-series → sparkline (filled only)
      # @param value   [String, nil]    pre-rendered scalar html (filled only)
      # @param loading [Boolean]        true → LoadingDots skeleton
      # @param no_data [Boolean]        true → NoData canvas + "n/a" (terminal)
      def initialize(key:, label:, token: nil, series: nil, value: nil, loading: false, no_data: false)
        @key     = key
        @label   = label
        @token   = token
        @series  = series
        @value   = value
        @loading = loading
        @no_data = no_data
      end

      attr_reader :key, :label, :series, :value

      def loading? = @loading
      def no_data? = @no_data
      def dom_id   = @token ? "#{@token}__metric_#{@key}" : nil
      def na       = Pito::Copy.render("pito.copy.analytics.na")
    end
  end
end
