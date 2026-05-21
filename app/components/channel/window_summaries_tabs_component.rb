# Phase 37 Wave A (window-summaries A-slice, 2026-05-19) — Variant 1.
#
# Tab-strip variant of the window-summaries section on `/channels`. A
# horizontal row of 5 window labels (`7d` / `28d` / `3m` / `365d` /
# `alltime`) sits at the top, with the currently-active window
# rendered in bold; the three stat cards (`subs Δ`, `views Δ`,
# `hours Δ`) for the active window render below.
#
# This A-slice ships INERT: the tab strip is purely visual and the
# default active window is `28d`. No JS, no URL state, no Stimulus
# wiring. The B-slice swap that wires up active-window selection
# (likely via the existing `?windows=` chip URL value or its own
# `?window=` single-select param) is a constant change at the view
# layer — only the `active_window` constructor arg moves.
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
class Channel::WindowSummariesTabsComponent < ViewComponent::Base
  WINDOWS = %w[7d 28d 3m 365d alltime].freeze
  DEFAULT_WINDOW = "28d"

  # @param channels [Array<Hash>] the selected channels (mock-data shape).
  # @param active_window [String] one of `WINDOWS`. Defaults to `"28d"`.
  def initialize(channels:, active_window: DEFAULT_WINDOW)
    @channels = channels
    @active_window = WINDOWS.include?(active_window.to_s) ? active_window.to_s : DEFAULT_WINDOW
  end

  attr_reader :channels, :active_window

  def windows
    WINDOWS
  end

  def active?(window)
    window == active_window
  end

  def active_summary
    @active_summary ||= Channel::Aggregator.window_summary(channels, active_window)
  end

  def subs_delta_formatted
    Pito::Formatter::CompactCount.call(active_summary[:subs_delta])
  end

  def views_delta_formatted
    Pito::Formatter::CompactCount.call(active_summary[:views_delta])
  end

  def watch_hours_delta_formatted
    Pito::Formatter::CompactHours.call(active_summary[:watch_hours_delta])
  end

  # Heading copy — matches the section's purpose. Caller may suppress
  # the heading by passing `heading: nil` if it ever lives inside a
  # `ShelfComponent` that already owns the heading row. For now the
  # component renders its own heading because the section is a
  # standalone block beneath Top Content (no surrounding shelf).
  def heading
    "Recent activity"
  end
end
