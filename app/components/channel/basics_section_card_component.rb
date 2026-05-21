# Phase 37 Wave A2 — `Channel::BasicsSectionCardComponent` (Variant 2).
#
# Four-cell card grid rendering of the Basics totals. Each cell is a
# bordered, subtly-tinted block with the value centered above the
# muted label. The most visually-prominent of the three variants —
# the cards push the four numbers up as a distinct UI surface.
#
# Spec: `docs/plans/beta/37-channels-revamp/specs/02-wave-a2-chip-wiring-basics.md`.
class Channel::BasicsSectionCardComponent < ViewComponent::Base
  def initialize(channels:)
    @channels = Array(channels)
  end

  def stats
    [
      { value: Channel::Aggregator.subscribers_total(@channels), label: "subs", formatter: Pito::Formatter::CompactCount },
      { value: Channel::Aggregator.views_total(@channels), label: "views", formatter: Pito::Formatter::CompactCount },
      { value: Channel::Aggregator.videos_total(@channels), label: "videos", formatter: Pito::Formatter::CompactCount },
      { value: Channel::Aggregator.watch_hours_total(@channels), label: "hours", formatter: Pito::Formatter::CompactHours }
    ]
  end
end
