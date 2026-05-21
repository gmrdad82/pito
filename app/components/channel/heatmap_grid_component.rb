# Phase 37 Wave A (heatmap A-slice) — "When your viewers are on
# YouTube" Variant 1: color-intensity grid.
#
# Renders a 7-row (Mon..Sun) × 24-column (00..23 hours) grid where
# every cell is colored by viewer-activity intensity. Each cell is a
# small fixed-size square; intensity drives a CSS opacity ramp over a
# single accent color so the canvas stays calm and monospace-aligned.
#
# Input shape — a single aggregated `Hash<String, Array<Integer>>`,
# the per-cell sum across whichever channels the caller selected. The
# component does NOT do channel aggregation; the view (or its caller)
# is responsible for summing per-cell across `@channels` and passing
# the resulting hash in. This keeps the component dumb and reusable
# (same shape works for a one-channel readout, an aggregate of N, or
# a future "compare two channels side-by-side" mode).
#
# Spec rules honored:
#
#   * Days are short labels (`Mon`..`Sun`) shown in the left column.
#   * Hours `0..23` shown across the top header row.
#   * Each cell colored from white/transparent at value 0 → accent
#     at the global max. We compute the max from the supplied hash so
#     a slice with low activity still uses the full intensity range.
#   * No red. Accent color is `--color-link` (project's bracket-link
#     blue) at varying opacity, which doubles as the channel-app's
#     existing primary accent. Falls back to a gentle border on the
#     value-0 cell so empty cells are still grid-visible.
#   * Compact: cell 16×16 px; row gap = 1 px hairline; integer pixel
#     values so the grid stays crisp on integer DPRs.
#   * No animation; pure CSS / inline styles; no Stimulus.
#
# Wave B will replace the mock-fed hash with a real query that
# joins `Channels::Stats.viewer_time_heatmap(...)`.
class Channel::HeatmapGridComponent < ViewComponent::Base
  DAYS = %w[Mon Tue Wed Thu Fri Sat Sun].freeze
  HOURS = (0..23).to_a.freeze

  # @param heatmap [Hash<String, Array<Integer>>] aggregated per-cell
  #   activity, keyed by short day name (`"Mon"`..`"Sun"`), each
  #   pointing at a 24-element integer array.
  def initialize(heatmap:)
    @heatmap = heatmap || {}
  end

  attr_reader :heatmap

  # Global maximum across the supplied hash. Drives the intensity
  # ramp. `1` floor so the division never divides by zero on an
  # entirely-blank slice.
  def max_value
    @max_value ||= begin
      values = heatmap.values.flatten.compact
      values.empty? ? 1 : [ values.max, 1 ].max
    end
  end

  # Intensity ratio for a cell value (0.0..1.0).
  def intensity(value)
    return 0.0 if value.nil? || max_value.zero?
    (value.to_f / max_value).clamp(0.0, 1.0)
  end

  # CSS background-color for a cell. Value 0 renders as a fully
  # transparent square with a 1 px border so the grid reads even on
  # the no-activity cells. Non-zero cells use a single accent color
  # at intensity-driven alpha.
  def cell_background(value)
    return "transparent" if value.nil? || value.zero?
    # `--color-link` resolves to #0000cc light / #bd93f9 dark. We use
    # the CSS `color-mix` function to mix the link color with the
    # background at a percentage that mirrors the intensity ramp so
    # the gradient looks correct in BOTH themes without hard-coding
    # two color sets. `color-mix` is supported in every evergreen
    # browser the app targets.
    pct = (intensity(value) * 100).round
    "color-mix(in srgb, var(--color-link) #{pct}%, transparent)"
  end

  # The 24 hour values for a day. Missing days render as zero-arrays
  # so the grid stays a 7×24 matrix even on partial inputs.
  def hours_for(day)
    Array(heatmap[day]).first(24).tap do |arr|
      while arr.length < 24
        arr << 0
      end
    end
  end
end
