module Tui
  # Beta 4 — Phase F2. TUI horizontal bar chart primitive. Renders a
  # list of label / bar / value triplets in a 3-column CSS grid;
  # each bar width is `(value / max) * 100%` and the fill color is
  # a 50%-transparent mix of the ambient `--section-accent` token.
  # The value column is right-aligned with tabular-nums so columns
  # of bars line up.
  #
  # Per ADR 0016 (TUI design system), this is the bar chart for
  # ranked categorical data — top videos, traffic sources, demo
  # buckets. Image 63 from the design exploration is the canonical
  # visual. The component is pure presentation; sorting + selection
  # happen in the caller.
  #
  # Each row is a Hash with keys `:label`, `:value`, and optionally
  # `:percent` (ignored — computed locally from the series max so
  # bars in the same chart share a denominator). Pass a
  # `value_format:` Proc to humanize the displayed number
  # (e.g. `->(n) { ActiveSupport::NumberHelper.number_to_human(n) }`).
  class BarChartComponent < ViewComponent::Base
    def initialize(rows:, value_format: nil)
      @rows = rows.to_a
      @value_format = value_format
    end

    attr_reader :rows, :value_format

    def format_value(value)
      value_format ? value_format.call(value) : value.to_s
    end

    def max_value
      rows.map { |r| r[:value].to_f }.max || 1.0
    end

    def percent(value)
      return 0 if max_value.zero?
      ((value.to_f / max_value) * 100).round(1)
    end
  end
end
