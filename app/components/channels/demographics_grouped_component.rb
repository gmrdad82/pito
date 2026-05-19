# Phase 37 Wave A (demographics A-slice, 2026-05-19) — V2 grouped
# horizontal bars for the `/channels` audience demographics section.
#
# One row per age bucket. Each row contains TWO bars side-by-side
# (male bar on top, female bar below) that grow rightward from a
# left-anchored axis. Each bar carries its percentage label at its
# right end. The 7 buckets stack vertically with `13-17` at the top
# and `65+` at the bottom — same order as V1 so the user can compare
# the two visuals against the same axis orientation.
#
# Layout (locked this slice):
#
#   ┌─────────── audience — grouped ───────────────────────────────┐
#   │                                                              │
#   │   13-17 │ male   ████████ 8%                                 │
#   │         │ female ████ 3%                                     │
#   │   18-24 │ male   ██████████████████████ 24%                  │
#   │         │ female ████████████ 12%                            │
#   │   ...                                                        │
#   │   65+   │ male   ▁ 0%                                        │
#   │         │ female ▁ 0%                                        │
#   │                                                              │
#   │   [ male █ ]  [ female █ ]                                   │
#   └──────────────────────────────────────────────────────────────┘
#
# Same data source + aggregator as V1. Differs in visual encoding:
# grouped bars on one side of a left-anchored axis instead of a two-
# sided pyramid. Easier to read absolute percentages; harder to read
# gender asymmetry at a glance.
#
# Tokens — identical to V1 (male = `--color-trend-up`; female =
# `--color-link`; axis hairline = `--color-border`). See V1 class
# comment for rationale.
class Channels::DemographicsGroupedComponent < ViewComponent::Base
  # @param channels [Array<Hash>] channel hashes from
  #   `Channels::MockData.channels`. Demographics may be inline on the
  #   hash (`:demographics`) or fetched lazily via
  #   `Channels::DemographicsMock.for(id)`.
  # @param weighted [Boolean] true → view-count-weighted aggregation
  #   across `channels`; false → simple mean.
  # @param title [String] section heading.
  def initialize(channels:, weighted: true, title: "audience — grouped")
    @channels = Array(channels)
    @weighted = weighted
    @title = title
  end

  attr_reader :channels, :weighted, :title

  def profile
    @profile ||= Channels::DemographicsMock.aggregate(channels_with_demographics, weighted: weighted)
  end

  def buckets
    Channels::DemographicsMock::AGE_BUCKETS
  end

  # Width budget for the longest bar in px. Both gender bars share
  # the same scale so a 24 % male bar and a 24 % female bar render at
  # identical widths.
  def bar_max_px
    260
  end

  def bar_width_px(pct)
    return 0 if max_pct.zero?
    (pct.to_f / max_pct * bar_max_px).round
  end

  def max_pct
    @max_pct ||= [ Channels::DemographicsMock.max_cell(profile), 1 ].max
  end

  def male_color
    "var(--color-trend-up)"
  end

  def female_color
    "var(--color-link)"
  end

  def format_pct(value)
    rounded = value.to_f.round(1)
    if (rounded - rounded.to_i).abs < 0.05
      "#{rounded.to_i}%"
    else
      format("%.1f%%", rounded)
    end
  end

  private

  def channels_with_demographics
    channels.map do |c|
      next c if c[:demographics]
      c.merge(demographics: Channels::DemographicsMock.for(c[:id]))
    end
  end
end
