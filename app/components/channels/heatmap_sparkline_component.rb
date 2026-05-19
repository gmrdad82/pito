# Phase 37 Wave A (heatmap A-slice) — "When your viewers are on
# YouTube" Variant 2: seven stacked sparklines (one per day).
#
# Renders seven mini line-charts stacked vertically. Each row shows
# the day label on the left and a 24-hour activity curve as an SVG
# `<path>` to the right. The Y-axis is shared across all 7 rows so
# the relative shapes are comparable at a glance — the busy days
# visibly tower over quiet days. Filled-area under the line keeps
# the shape readable at small heights.
#
# Same input shape as `Channels::HeatmapGridComponent`: a single
# pre-aggregated `Hash<String, Array<Integer>>`. The view (or its
# caller) does the channel-aggregation summing.
#
# Spec rules honored:
#
#   * Each sparkline is an SVG `<path>` (line) + a complementary
#     `<path>` (filled area). Sizes: 24 hours mapped across 360 px
#     width × 32 px height. Inline SVG is fine for 7 small charts;
#     no client-side library needed.
#   * Day label left-aligned in a fixed 36 px column.
#   * Shared Y-axis: max across the entire supplied hash drives every
#     row's scale.
#   * No animation; no Stimulus; no red.
#   * Color: `--color-link` for the line stroke; line-color at low
#     opacity for the area fill so the curve reads even at low
#     amplitudes.
#
# Wave B replaces the mock-fed hash with a real query.
class Channels::HeatmapSparklineComponent < ViewComponent::Base
  DAYS = %w[Mon Tue Wed Thu Fri Sat Sun].freeze
  HOURS = (0..23).to_a.freeze

  # Each sparkline cell in pixels.
  SPARKLINE_WIDTH = 360
  SPARKLINE_HEIGHT = 32

  def initialize(heatmap:)
    @heatmap = heatmap || {}
  end

  attr_reader :heatmap

  # Global maximum drives the shared Y axis. `1` floor avoids zero
  # division on entirely-blank input.
  def max_value
    @max_value ||= begin
      values = heatmap.values.flatten.compact
      values.empty? ? 1 : [ values.max, 1 ].max
    end
  end

  # Returns the 24 hour values for a day (zero-padded if short).
  def hours_for(day)
    Array(heatmap[day]).first(24).tap do |arr|
      while arr.length < 24
        arr << 0
      end
    end
  end

  # Build the SVG `points` string for the line path. X spans 0 →
  # SPARKLINE_WIDTH across 24 hours; Y is inverted (SVG origin at
  # top-left) so high activity bumps upward visually.
  #
  # Returns a string like `"0,30 16,28 ..."` suitable for the
  # `polyline points=` attribute (we use a polyline for the stroke
  # and a separate `polygon` for the fill, both fed from the same
  # point list).
  def points_for(day)
    values = hours_for(day)
    step = SPARKLINE_WIDTH.to_f / (HOURS.size - 1)
    values.each_with_index.map do |v, i|
      x = (i * step).round(2)
      ratio = (v.to_f / max_value).clamp(0.0, 1.0)
      # Leave a 2 px top + bottom margin inside the row so the path
      # doesn't kiss the edges.
      y_inner = SPARKLINE_HEIGHT - 4
      y = (SPARKLINE_HEIGHT - 2 - (ratio * y_inner)).round(2)
      "#{x},#{y}"
    end.join(" ")
  end

  # Polygon points for the filled-area variant — line points +
  # bottom-right corner + bottom-left corner so the polygon closes
  # along the baseline.
  def area_points_for(day)
    base = points_for(day)
    "#{base} #{SPARKLINE_WIDTH},#{SPARKLINE_HEIGHT - 2} 0,#{SPARKLINE_HEIGHT - 2}"
  end
end
