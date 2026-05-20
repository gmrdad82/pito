module Tui
  # Beta 4 — Phase F2. TUI demographic-pyramid primitive. Renders a
  # five-column grid per row: left-value % | left-bar | label |
  # right-bar | right-value %. Left bars (Dracula green) grow right
  # from the center; right bars (Dracula purple) grow right from
  # the label. Bar widths are `(value / series_max) * 100%` against
  # the SHARED maximum across both sides so the two halves are
  # directly comparable.
  #
  # Per ADR 0016 (TUI design system), this is the chart for paired
  # bucket comparisons — male vs female age, owned vs played per
  # platform, subscribed vs anonymous traffic. Image 62 from the
  # design exploration is the canonical visual.
  #
  # Each row is a Hash with keys `:left`, `:label`, `:right`. The
  # left and right values render as raw percentages (suffixed `%`
  # in the template); the consumer is responsible for already
  # normalizing them to the percent space.
  class PyramidComponent < ViewComponent::Base
    def initialize(rows:)
      @rows = rows.to_a
    end

    attr_reader :rows

    def max_value
      [ rows.map { |r| r[:left].to_f }.max, rows.map { |r| r[:right].to_f }.max ].compact.max || 1.0
    end

    def percent(value)
      return 0 if max_value.zero?
      ((value.to_f / max_value) * 100).round(1)
    end
  end
end
