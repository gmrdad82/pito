# Phase 37 (audience-geography A-slice, 2026-05-19) — Variant 2:
# horizontal bar chart, top-8 countries.
#
# Visualization-first: each row is a wide bar whose length tracks the
# absolute view count (not percentage). The longest bar fills the full
# track width; shorter bars scale relative to the max. The value on the
# right uses `Formatting::CompactCount` so K / M / B suffixes keep the
# numbers compact regardless of channel mix.
#
# Row layout:
#
#   [ country name (120px) ][ bar (1fr, scaled to max) ][ value (72px) ]
#
# Aggregation rule mirrors `Channels::GeographyListComponent` — sum
# `:views` per `:country_code`, rank descending, take top TOP_N. The bar
# fill uses `var(--color-link)` (canonical bracketed-link blue) so the
# variant family stays visually consistent across the three options.
class Channels::GeographyBarComponent < ViewComponent::Base
  TOP_N = 8

  def initialize(channels:)
    @channels = Array(channels)
  end

  def aggregated
    return @aggregated if defined?(@aggregated)

    sums = Hash.new(0)
    names = {}
    @channels.each do |c|
      Array(c[:geography]).each do |row|
        code = row[:country_code].to_s
        sums[code] += row[:views].to_i
        names[code] ||= row[:country_name].to_s
      end
    end

    total = sums.values.sum
    return @aggregated = nil if total.zero?

    top = sums.sort_by { |_, v| -v }.first(TOP_N)
    max_views = top.first.last.to_f
    @aggregated = top.map do |code, views|
      {
        country_code: code,
        country_name: names[code],
        views: views,
        # Width as a 0..100 percentage of the LARGEST bar (not of the
        # aggregate total) so the visual emphasizes relative magnitude.
        width_pct: max_views.zero? ? 0 : (views.to_f * 100 / max_views).round(1)
      }
    end
  end

  def has_data?
    !aggregated.nil?
  end

  def compact(value)
    Formatting::CompactCount.call(value)
  end
end
