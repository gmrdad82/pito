# Phase 37 Wave A (window-summaries A-slice, 2026-05-19) — Variant 2.
#
# Side-by-side window-cards variant of the window-summaries section on
# `/channels`. Five small cards, one per window
# (`7d` / `28d` / `3m` / `365d` / `alltime`), each carrying the window
# label up top and the three stat lines (`subs Δ`, `views Δ`,
# `hours Δ`) stacked below. All five windows visible at once for
# scan-and-compare.
#
# This A-slice ships INERT: no selection state, no JS, no URL wiring.
#
# Data source: `Channel::Aggregator.window_summary(channels, window)`
# returns `{ subs_delta:, views_delta:, watch_hours_delta: }` summed
# across the provided channels. The `alltime` branch falls back to the
# absolute totals (`subscribers_total` / `views_total` /
# `watch_hours_total`).
#
# Counts go through `Pito::Formatter::CompactCount` (subs Δ + views Δ) and
# `Pito::Formatter::CompactHours` (hours Δ) — same formatters the ID-card
# uses so number-format conventions stay consistent across the page.
class Channel::WindowSummariesGridComponent < ViewComponent::Base
  WINDOWS = %w[7d 28d 3m 365d alltime].freeze

  # @param channels [Array<Hash>] the selected channels (mock-data shape).
  def initialize(channels:)
    @channels = channels
  end

  attr_reader :channels

  def windows
    WINDOWS
  end

  # Build a per-window precomputed array so the template stays simple.
  # Each entry: `{ window:, subs:, views:, hours: }` with already-
  # formatted strings ready to splat into ERB.
  def cards
    @cards ||= WINDOWS.map do |window|
      summary = Channel::Aggregator.window_summary(channels, window)
      {
        window: window,
        subs: Pito::Formatter::CompactCount.call(summary[:subs_delta]),
        views: Pito::Formatter::CompactCount.call(summary[:views_delta]),
        hours: Pito::Formatter::CompactHours.call(summary[:watch_hours_delta])
      }
    end
  end

  def heading
    "Recent activity"
  end
end
