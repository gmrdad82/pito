# Phase 37 Wave A (demographics A-slice, 2026-05-19) — V1 population
# pyramid for the `/channels` audience demographics section.
#
# Two-sided horizontal bar chart, age buckets stacked vertically with
# the youngest (`13-17`) at the top and the oldest (`65+`) at the
# bottom. Male bars extend leftward from a shared center axis; female
# bars extend rightward. Each bar carries its percentage label on the
# outer (away-from-axis) end. Age labels sit on the center axis.
#
# Layout (locked this slice):
#
#   ┌─────────── audience ───────────┐
#   │                                │
#   │   ░░░░ male   8% │ 13-17 │ 6% female ░░░░         │
#   │   ████████ 22%   │ 18-24 │ 15% ██████             │
#   │    ...                                            │
#   │   ░ 1%           │ 65+   │ 0%                     │
#   │                                                   │
#   │   [ male █ ]  [ female █ ]                        │
#   └───────────────────────────────────────────────────┘
#
# Aggregation: view-count-weighted mean across the channel list passed
# in. Wave B can swap the source — the public surface
# (`profile = { male: {bucket=>pct}, female: {bucket=>pct} }`) is
# stable.
#
# Tokens:
#   * Bar colors — distinct enough to read at a glance without using
#     red (`var(--color-danger)` / `#cc0000` is reserved for
#     destructive actions per `CLAUDE.md` §Visual style). Male uses
#     `var(--color-trend-up)` (the existing greenish trend-up tone);
#     female uses `var(--color-link)` (the existing link blue). Both
#     tokens auto-flip to their dark-theme variants via the existing
#     `[data-theme="dark"]` block in `application.css`.
#   * Center axis hairline — `1px solid var(--color-border)`, matches
#     `hr.hairline` convention.
#   * Bar bg fill (zero region) — none; bars are simple solid
#     rectangles in a flex row. The percentage label sits in a
#     muted-color span just past the bar's outer end.
#   * Body font-size — 13 px (CLAUDE.md visual style §Font).
#
# Inert — no Stimulus, no actions.
class Channels::DemographicsPyramidComponent < ViewComponent::Base
  # @param channels [Array<Hash>] channel hashes from
  #   `Channels::MockData.channels`. Demographics may be inline on the
  #   hash (`:demographics`) or fetched lazily via
  #   `Channels::DemographicsMock.for(id)`.
  # @param weighted [Boolean] true → view-count-weighted aggregation
  #   across `channels`; false → simple mean.
  # @param title [String] section heading (e.g. "audience (pyramid)").
  def initialize(channels:, weighted: true, title: "audience — pyramid")
    @channels = Array(channels)
    @weighted = weighted
    @title = title
  end

  attr_reader :channels, :weighted, :title

  # Aggregated profile. Calls into the mock module so swapping data
  # source is a one-line change.
  def profile
    @profile ||= Channels::DemographicsMock.aggregate(channels_with_demographics, weighted: weighted)
  end

  def buckets
    Channels::DemographicsMock::AGE_BUCKETS
  end

  # Width budget for the longest bar on each side, in px. Bars on
  # either side scale linearly against `max_pct`.
  def half_bar_max_px
    180
  end

  # Per-bar pixel width for a given percent. Capped at `half_bar_max_px`.
  def bar_width_px(pct)
    return 0 if max_pct.zero?
    (pct.to_f / max_pct * half_bar_max_px).round
  end

  # Highest single-cell percentage across the aggregated profile —
  # drives the bar scale so the longest bar fills `half_bar_max_px`.
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
    # Drop trailing `.0` so whole percentages render as `12%` not
    # `12.0%`. Keep one decimal otherwise so the difference between
    # `12.3%` and `12.7%` survives the aggregate.
    rounded = value.to_f.round(1)
    if (rounded - rounded.to_i).abs < 0.05
      "#{rounded.to_i}%"
    else
      format("%.1f%%", rounded)
    end
  end

  private

  # Ensure each channel hash has a `:demographics` key — either inline
  # (when the parallel mock_data.rb slice added it) or backfilled from
  # `Channels::DemographicsMock.for`.
  def channels_with_demographics
    channels.map do |c|
      next c if c[:demographics]
      c.merge(demographics: Channels::DemographicsMock.for(c[:id]))
    end
  end
end
