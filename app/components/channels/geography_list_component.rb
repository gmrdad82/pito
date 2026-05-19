# Phase 37 (audience-geography A-slice, 2026-05-19) — Variant 1:
# ranked top-10 country list with percentage bars.
#
# Renders the aggregated audience geography (country → views) as a
# vertical list of up to 10 rows. Each row layout:
#
#   [ flag (emoji) ][ code (24px) ][ country name (fills) ][ bar ][ % ]
#
# The bar width tracks the country's share of the aggregate (0..100),
# drawn as a filled rectangle inside a faint `--color-border` track so
# even a sub-1% slice has visible context. Numbers use tabular-nums to
# keep the percentage column right-aligned across rows.
#
# Aggregation rule — sum `:views` per `:country_code` across the
# provided channel hashes; rank descending; take top 10; compute each
# row's percentage of the aggregate total. Pure function — no I/O, no
# Stimulus, no Chart.js.
#
# The "flag emoji" is built from the 2-letter ISO code by mapping each
# letter to its regional-indicator codepoint (U+1F1E6 + (code - 'A')).
# That's deterministic and works for every entry in `Channels::MockData`
# without a lookup table.
#
# Color choice — the bar fill uses `var(--color-link)` (the canonical
# bracketed-link blue) so the visual reads as "neutral chart accent" per
# the dispatch's "neutral chart accent" guidance. Red is reserved for
# destructive actions (CLAUDE.md visual rules).
class Channels::GeographyListComponent < ViewComponent::Base
  TOP_N = 10

  def initialize(channels:)
    @channels = Array(channels)
  end

  # Returns an Array<Hash> sorted descending by views, capped at TOP_N.
  # Each entry: { country_code:, country_name:, views:, percent: }.
  # `percent` is a Float (1 decimal precision via `.round(1)`).
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
    @aggregated = top.map do |code, views|
      {
        country_code: code,
        country_name: names[code],
        views: views,
        percent: (views.to_f * 100 / total).round(1)
      }
    end
  end

  def has_data?
    !aggregated.nil?
  end

  # Build the regional-indicator emoji pair for a 2-letter country
  # code. Returns the string of two codepoints joined.
  def flag_for(code)
    return "" unless code.is_a?(String) && code.length == 2

    base = 0x1F1E6 - "A".ord
    code.upcase.chars.map { |ch| (base + ch.ord).chr(Encoding::UTF_8) }.join
  end
end
