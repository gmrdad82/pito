module Tui
  # Beta 4 — Phase F2. TUI ASCII progress bar primitive. Renders a
  # fixed-width bar via `▓` (filled) and `░` (empty) wrapped in
  # literal `[ ]` brackets, followed by a `N/M` counter label. The
  # bar width is a constructor arg (default 10 cells), the fill is
  # `current / total` clamped to [0, width].
  #
  # Per ADR 0016 (TUI design system), this is the STATIC bar — the
  # progress-mode rendering of an animated job. For determinate
  # transient work the existing `Tui::IndicatorComponent` (mode
  # `:progress`) is the right primitive; use this one when you want
  # a stand-alone progress display embedded in a row, cell, or
  # status-bar segment, with no spinner cadence.
  #
  # Negative or out-of-range inputs are clamped silently; a total
  # of zero renders an empty bar (no division-by-zero, no error).
  # The counter label uses `tabular-nums` so columns of bars line up
  # under each other.
  class ProgressBarComponent < ViewComponent::Base
    def initialize(current:, total:, width: 10)
      @current = current.to_i
      @total = total.to_i
      @width = width.to_i
    end

    attr_reader :current, :total, :width

    def filled_count
      return 0 if total <= 0
      ((current.to_f / total) * width).round.clamp(0, width)
    end

    def rendered
      ("▓" * filled_count) + ("░" * (width - filled_count))
    end

    def label
      "#{current}/#{total}"
    end
  end
end
