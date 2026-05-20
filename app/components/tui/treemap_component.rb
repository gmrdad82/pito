module Tui
  # Beta 4 — Phase F2. TUI treemap primitive. Renders proportionally
  # sized tiles via CSS flex with `flex-grow` set to the raw value
  # — bigger value, bigger tile. Tile background is
  # `--section-accent` mixed at `percent%` against transparent (so
  # the dominant tile is the most saturated, smaller tiles fade).
  # Each tile shows a 2-3 char code label (e.g. `US`, `UK`, `DE`)
  # and the share as a tabular-numeric percent.
  #
  # Per ADR 0016 (TUI design system), this is the chart for
  # share-of-total breakdowns — geography, platform mix, language
  # share. Image 64 from the design exploration shows the canonical
  # visual; a flex-grow approach keeps the layout responsive without
  # an SVG render step.
  #
  # `rows:` should be sorted by `:value` descending before the
  # component is rendered — the component does NOT sort internally
  # (the caller may want a different order; e.g. alphabetical for
  # a comparison snapshot).
  class TreemapComponent < ViewComponent::Base
    def initialize(rows:)
      @rows = rows.to_a
    end

    attr_reader :rows

    def total
      rows.map { |r| r[:value].to_f }.sum
    end

    def percent(value)
      return 0 if total.zero?
      ((value.to_f / total) * 100).round(1)
    end
  end
end
