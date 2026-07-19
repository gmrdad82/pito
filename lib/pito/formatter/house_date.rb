# frozen_string_literal: true

# Pure functions. The house date/time shape — the one every stamp on every
# surface renders through (owner decree). Two entry points:
#
#   date(d)  — a Date (or date-like, via #to_date): current year "%-d %b"
#              (no year, no leading zero — "4 Jun", "23 Feb"); any OTHER year,
#              past or future, "%-d %b '%y" ("5 Jun '25", "26 Jul '27"). A
#              date-only value never collapses on "today" — dropping the date
#              would leave nothing to show.
#
#   stamp(time, fallback:) — a Time/DateTime/ActiveSupport::TimeWithZone or
#              nil: blank returns `fallback`. Otherwise TODAY collapses to
#              bare "%H:%M" (the date drops entirely — collapse-everywhere);
#              current year "%-d %b %H:%M"; any other year "%-d %b '%y %H:%M".
#
# Both read Time.zone.today at CALL time (not frozen at render setup), so a
# re-rendered stamp ages naturally — a message that was "today" yesterday now
# carries its day, exactly as TimestampPrefixComponent already behaved before
# this module existed; that three-tier rule is generalized here so every
# other surface (SyncStamp, and whatever comes next) shares ONE implementation.
#
# Month-granularity labels (no day component at all — e.g. a release month
# badge/chart tick: current year "%b", other years "%b '%y") follow the same
# rule but aren't a third entry point here — nothing calls through this
# module for that shape yet.
module Pito
  module Formatter
    module HouseDate
      module_function

      # @param d [Date, #to_date] a date-only value (no time component).
      # @return [String] "%-d %b" (current year) or "%-d %b '%y" (any other year).
      def date(d)
        d = d.to_date
        d.year == Time.zone.today.year ? d.strftime("%-d %b") : d.strftime("%-d %b '%y")
      end

      # @param time [Time, DateTime, ActiveSupport::TimeWithZone, nil]
      # @param fallback [String] returned when `time` is blank.
      # @return [String] the house stamp, rendered in the app's local zone.
      def stamp(time, fallback: "—")
        return fallback if time.blank?

        local = time.in_time_zone
        today = Time.zone.today

        if local.to_date == today
          local.strftime("%H:%M")
        elsif local.year == today.year
          local.strftime("%-d %b %H:%M")
        else
          local.strftime("%-d %b '%y %H:%M")
        end
      end
    end
  end
end
