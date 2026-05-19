# Phase 37 (device-types A-slice) — Variant 2: horizontal bar list.
#
# Renders the aggregated device-type viewership breakdown as 5 stacked
# horizontal bars, one per device. Each row layout:
#
#   [ device name (fixed width) ][ bar ][ percentage (right-aligned) ]
#
# The bar width tracks the device's percentage (0..100), drawn as a
# filled rectangle inside a 100%-wide track. The track itself uses
# `--color-border` as a faint backdrop so even a 2% slice has visible
# context.
#
# Aggregation rule mirrors `Channels::DeviceTypesDonutComponent` — view-
# count-weighted average across selected channels, rounded + re-
# normalized to 100. The two components could share a service later;
# this iteration keeps the helper inline to stay scoped.
#
# Pure CSS / HTML — no Chart.js, no Stimulus.
class Channels::DeviceTypesBarsComponent < ViewComponent::Base
  DEVICE_ORDER = [ "Mobile", "Computer", "TV", "Tablet", "Game console" ].freeze

  # Bar fill colors — link-blue family for the top two tiers, neutral
  # greys below. Matches the donut variant exactly so flipping between
  # the two reads as the same data.
  BAR_COLORS = {
    "Mobile"       => "#0000cc",
    "Computer"     => "#4d4dff",
    "TV"           => "#888888",
    "Tablet"       => "#bbbbbb",
    "Game console" => "#555555"
  }.freeze

  def initialize(channels:)
    @channels = Array(channels)
  end

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

    rounded = raw.transform_values { |v| v.round }
    drift = 100 - rounded.values.sum
    if drift != 0
      largest = rounded.max_by { |_, v| v }.first
      rounded[largest] += drift
    end

    @aggregated = DEVICE_ORDER.map { |name| { name: name, percent: rounded[name] } }
  end

  def has_data?
    !aggregated.nil?
  end

  def color_for(name)
    BAR_COLORS.fetch(name, "var(--color-muted)")
  end
end
