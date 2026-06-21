# frozen_string_literal: true

module Pito
  module Analytics
    # Computes the directional trend between a current and previous period value.
    #
    # == Usage
    #
    #   Pito::Analytics::Trend.for(current: 110, previous: 100)  # => :up
    #   Pito::Analytics::Trend.for(current: 90,  previous: 100)  # => :down
    #   Pito::Analytics::Trend.for(current: 101, previous: 100)  # => :steady
    #   Pito::Analytics::Trend.for(current: 5,   previous: nil)  # => :none
    #   Pito::Analytics::Trend.for(current: 5,   previous: 0)    # => :none
    #
    # == :none semantics
    #
    # A percentage-change ratio requires a non-zero denominator. We return
    # `:none` — not a direction — when `previous` is nil (no data available,
    # e.g. lifetime windows have no prior interval) or zero (a baseline of zero
    # makes any ratio undefined / misleading). Callers should hide or grey-out
    # the trend indicator when the result is `:none`.
    #
    # == Band
    #
    # `band` is the symmetric fractional threshold for "steady": when
    # |Δ / previous| ≤ band the result is `:steady`. The default of 0.03 means
    # changes within ±3 % are treated as flat. Pass a tighter or wider value
    # at the call site when the metric warrants it.
    module Trend
      module_function

      # @param current  [Numeric]       the current-period value
      # @param previous [Numeric, nil]  the prior-period value (nil = no data)
      # @param band     [Float]         fractional steady-zone half-width (default 0.03)
      # @return [Symbol] :up | :down | :steady | :none
      def for(current:, previous:, band: 0.03)
        return :none if previous.nil? || previous.zero?

        delta = (current - previous).to_f / previous.abs

        if delta.abs <= band
          :steady
        elsif delta > 0
          :up
        else
          :down
        end
      end
    end
  end
end
