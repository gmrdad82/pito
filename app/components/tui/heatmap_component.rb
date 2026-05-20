module Tui
  # Beta 4 — Phase F2. TUI heatmap primitive. Renders a 7-row
  # (Mon..Sun) × N-col (default 24-hour) grid of cells; each cell
  # background is `--section-accent` mixed at `intensity * 60%`
  # against transparent, where intensity is `value / series_max`
  # clamped to [0, 1]. Cells with no data render at intensity 0
  # (fully transparent — only the soft border outlines them).
  #
  # Per ADR 0016 (TUI design system), this is the activity-density
  # chart for time-by-day patterns — channel publish cadence,
  # viewer engagement windows, sync error clusters. Image 64 from
  # the design exploration is the canonical visual.
  #
  # `data:` is a Hash keyed by day label (`"Mon"`, `"Tue"`, …) whose
  # values are arrays of 24 numbers (one per hour). `hours:` lets
  # callers override the hour range (e.g. `(8..20).to_a` for a
  # working-hours strip). Missing keys or short arrays render as
  # zero — no errors, no exceptions.
  class HeatmapComponent < ViewComponent::Base
    DAYS = %w[Mon Tue Wed Thu Fri Sat Sun].freeze

    def initialize(data:, hours: (0..23).to_a)
      @data = data
      @hours = hours
    end

    attr_reader :data, :hours

    def intensity(day, hour)
      val = data.dig(day, hour) || 0
      max = data.values.flatten.max.to_f
      return 0 if max.zero?
      val.to_f / max
    end
  end
end
