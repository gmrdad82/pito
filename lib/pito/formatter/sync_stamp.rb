# frozen_string_literal: true

# Pure function. Delegates to Pito::Formatter::HouseDate.stamp — the house
# stamp shape used across the detail cards, the linked-game card, the
# schedule confirmations, and the AI kv-table (the `strftime` recurred 7×
# app-wide before this module existed). The DD-MM-YYYY era is over: this now
# emits the house stamp — bare "%H:%M" for today (the date drops entirely),
# "%-d %b %H:%M" for the current year, "%-d %b '%y %H:%M" for any other year.
# The name and the `fallback:` kwarg stay put — 16 call sites depend on them.
#
# Input: a Time/DateTime/ActiveSupport::TimeWithZone or nil. The value is
# rendered in the app's local zone (`in_time_zone`).
# Output: the house stamp, or `fallback` (default "—") when the input is
# blank — callers with bespoke never-synced copy pass it in.
#
# Examples (assuming "today" is 19 Jul 2026):
#   call(Time.zone.local(2026, 7, 19, 14, 30))  => "14:30"           (today)
#   call(Time.zone.local(2026, 6, 2, 16, 30))   => "2 Jun 16:30"     (this year)
#   call(Time.zone.local(2025, 6, 2, 16, 30))   => "2 Jun '25 16:30" (other year)
#   call(nil)                                    => "—"
#   call(nil, fallback: "never synced")          => "never synced"
module Pito
  module Formatter
    module SyncStamp
      module_function

      def call(time, fallback: "—")
        HouseDate.stamp(time, fallback: fallback)
      end
    end
  end
end
