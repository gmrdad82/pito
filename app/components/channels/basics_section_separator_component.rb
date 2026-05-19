# Phase 37 Wave A2 — `Channels::BasicsSectionSeparatorComponent` (Variant 3).
#
# Four-stat row separated by vertical hairlines. Larger value (22px
# bold) over a muted label, with `border-left` rules between the
# cells. No background tint, no border around the whole — minimal
# chrome, the page's body whitespace carries the cells.
#
# Spec: `docs/plans/beta/37-channels-revamp/specs/02-wave-a2-chip-wiring-basics.md`.
class Channels::BasicsSectionSeparatorComponent < ViewComponent::Base
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
