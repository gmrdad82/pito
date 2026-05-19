# Phase 37 (device-types A-slice) — Variant 1: CSS donut chart.
#
# Renders the aggregated device-type viewership breakdown as a
# `conic-gradient` donut with a center label showing the largest
# device and its percentage, plus a right-side legend with bracketed
# device names and percentages.
#
# Aggregation rule: across the selected channels (already filtered by
# the controller against `?channels=`), each channel's device-type
# percentages are weighted by that channel's `view_count` and averaged
# into a single percentage per device. The result re-normalizes to 100
# so the donut renders cleanly even if rounding drifts by 1-2 points.
#
# Color choices for the 5 device slices are pulled directly from the
# already-used neutral palette (`--color-link` / `--color-muted` /
# `--color-text` etc.) and additional muted greys derived from the
# existing design tokens — every slice is link-blue-ish or a neutral
# tone, no red (red is reserved per CLAUDE.md visual style §Red).
#
# Pure CSS / HTML — no Chart.js, no SVG, no Stimulus. Iteration only.
class Channels::DeviceTypesDonutComponent < ViewComponent::Base
  DEVICE_ORDER = [ "Mobile", "Computer", "TV", "Tablet", "Game console" ].freeze

  # Five distinct, theme-agnostic slice colors. Mobile + Computer get
  # the link-blue family (most viewers); TV + Tablet + console pick up
  # neutral / muted greys so they read as secondary tiers.
  SLICE_COLORS = {
    "Mobile"       => "#0000cc",
    "Computer"     => "#4d4dff",
    "TV"           => "#888888",
    "Tablet"       => "#bbbbbb",
    "Game console" => "#555555"
  }.freeze

  # @param channels [Array<Hash>] entries from `Channels::MockData.channels`.
  #   Each entry must carry `:view_count` (Integer) and `:device_types`
  #   (Hash<String, Integer> where each value is a percent 0..100 and
  #   the values sum to 100).
  def initialize(channels:)
    @channels = Array(channels)
  end

  # Aggregate percentages across selected channels, weighted by
  # `view_count`. Returns an ordered array of
  # `{ name:, percent: }` hashes following `DEVICE_ORDER`. When no
  # channels are selected (or none carry views), returns nil so the
  # view renders an em-dash placeholder instead of an empty donut.
  def aggregated
    return @aggregated if defined?(@aggregated)

    total_weight = @channels.sum { |c| c[:view_count].to_i }
    return @aggregated = nil if total_weight.zero?

    raw = DEVICE_ORDER.each_with_object({}) do |device, acc|
      weighted = @channels.sum do |c|
        pct = (c[:device_types] || {})[device].to_i
        pct * c[:view_count].to_i
      end
      acc[device] = weighted.to_f / total_weight
    end

    # Round + re-normalize to 100 to absorb floating drift.
    rounded = raw.transform_values { |v| v.round }
    drift = 100 - rounded.values.sum
    if drift != 0
      # Push drift onto the largest slice.
      largest = rounded.max_by { |_, v| v }.first
      rounded[largest] += drift
    end

    @aggregated = DEVICE_ORDER.map { |name| { name: name, percent: rounded[name] } }
  end

  def has_data?
    !aggregated.nil?
  end

  # Build the `conic-gradient` CSS string for the donut. Walks the
  # aggregated list in order, accumulating a running degree pointer.
  def conic_gradient_css
    return "" unless has_data?

    deg = 0.0
    stops = aggregated.map do |slice|
      from = deg
      to = deg + (slice[:percent] * 3.6)
      deg = to
      "#{SLICE_COLORS.fetch(slice[:name])} #{from}deg #{to}deg"
    end
    "conic-gradient(#{stops.join(', ')})"
  end

  def largest_slice
    aggregated&.max_by { |s| s[:percent] }
  end

  def color_for(name)
    SLICE_COLORS.fetch(name, "var(--color-muted)")
  end
end
