# Phase 37 Wave A1 (2026-05-19 chip-row consolidation) —
# `Formatting::CurrentChannelFilterChips`.
#
# Pure function. Returns the dynamic year + month filter-chip definitions
# the `/channels` chip row appends after the static time-window chips
# ([7d] [28d] [3m] [365d] [alltime]).
#
# Rules (locked 2026-05-19, user):
#
#   * Year chips: previous year + current year. Derived from
#     `Date.current.year` (and `- 1`). Label and URL value are both the
#     four-digit year string (e.g. "2025", "2026"). January-edge case is
#     covered transparently — the previous-year chip already represents
#     the calendar year the December-of-previous-year month chip falls
#     inside.
#
#   * Month chips: previous month + current month. Derived from
#     `Date.current.beginning_of_month` and `1.month.ago.beginning_of_month`.
#     Display label is the 3-letter `%b` abbreviation (e.g. "Apr",
#     "May"). URL value is the lowercase `%b` (e.g. "apr", "may") so
#     the URL stays case-insensitive and matches the existing
#     `?calendar=` csv pattern. Year crossing (e.g. previous-month in
#     January → "Dec") is preserved by the underlying date arithmetic;
#     the matching year chip carries the year context.
#
# Pure — no I/O, no Rails dependency beyond `Date` / `1.month.ago`.
# Reusable by future video / channels / games filter rows that need
# the same "previous + current period" chip set.
module Formatting
  module CurrentChannelFilterChips
    module_function

    # @param today [Date] inject for tests; defaults to `Date.current`.
    # @return [Hash] `{ years: [{label:, value:}, ...], months: [{label:, value:}, ...] }`.
    #   Each array carries the previous-period entry first then the
    #   current-period entry — render order matches the locked layout
    #   `[ ] <prev-year> [ ] <current-year> [ ] <prev-month> [ ] <current-month>`.
    def call(today: Date.current)
      prev_year = today.year - 1
      current_year = today.year

      current_month_date = today.beginning_of_month
      prev_month_date = current_month_date.prev_month

      {
        years: [
          { label: prev_year.to_s, value: prev_year.to_s },
          { label: current_year.to_s, value: current_year.to_s }
        ],
        months: [
          { label: prev_month_date.strftime("%b"), value: prev_month_date.strftime("%b").downcase },
          { label: current_month_date.strftime("%b"), value: current_month_date.strftime("%b").downcase }
        ]
      }
    end
  end
end
