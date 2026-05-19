# Phase 37 Wave A2 — `Channels::BasicsSectionInlineComponent` (Variant 1).
#
# Single-line inline rendering of the four Basics totals
# (subscribers / views / videos / watch hours) across the selected
# channels. Each stat reads as `<value> <muted label>` separated by
# generous horizontal gaps. The most compact of the three variants.
#
# Spec: `docs/plans/beta/37-channels-revamp/specs/02-wave-a2-chip-wiring-basics.md`.
class Channels::BasicsSectionInlineComponent < ViewComponent::Base
  # @param channels [Array<Hash>] entries from
  #   `Channels::MockData.channels` (or, in Wave B, the real query
  #   layer producing the same shape). Already filtered by the
  #   controller against `?channels=`.
  def initialize(channels:)
    @channels = Array(channels)
  end

  def stats
    [
      { value: Channels::Aggregator.subscribers_total(@channels), label: "subs", formatter: Formatting::CompactCount },
      { value: Channels::Aggregator.views_total(@channels), label: "views", formatter: Formatting::CompactCount },
      { value: Channels::Aggregator.videos_total(@channels), label: "videos", formatter: Formatting::CompactCount },
      { value: Channels::Aggregator.watch_hours_total(@channels), label: "hours", formatter: Formatting::CompactHours }
    ]
  end
end
