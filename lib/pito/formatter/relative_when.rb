# frozen_string_literal: true

# Pure function. Humanised FUTURE relative time — the schedule slate's go-live
# column. Tiered relative → absolute, 24h clock, rendered in the app's local zone:
#
#   < 1 hour   → "in 45 minutes" / "in a minute" / "any moment now"
#   same day   → "in 3 hours" / "in an hour"
#   tomorrow   → "tomorrow at noon" (noon=12:00 / midnight=00:00) / "tomorrow at 09:00"
#   2–6 days   → "in 2 days"
#   ≥ 7 days   → "on 1st of March" (+ year when it is not the current year)
#
# Input: a Time / TimeWithZone (expected to be in the future) or nil. A blank or
# non-future value returns `fallback` (default "—") — the slate only lists future
# publish_at, but the guard keeps the helper total.
module Pito
  module Formatter
    module RelativeWhen
      module_function

      def call(time, now: Time.current, fallback: "—")
        return fallback if time.blank?

        t   = time.in_time_zone
        ref = now.in_time_zone
        return fallback if t <= ref

        days = (t.to_date - ref.to_date).to_i
        secs = (t - ref).to_i

        if secs < 3600 then in_minutes(secs)
        elsif days.zero? then in_hours(secs)
        elsif days == 1  then "tomorrow at #{clock(t)}"
        elsif days <= 6  then "in #{days} days"
        else "on #{ordinal(t.day)} of #{t.strftime('%B')}#{year_suffix(t, ref)}"
        end
      end

      def in_minutes(secs)
        minutes = (secs / 60.0).round
        return "any moment now" if minutes <= 0
        return "in a minute"    if minutes == 1

        "in #{minutes} minutes"
      end

      def in_hours(secs)
        hours = (secs / 3600.0).round
        hours = 1 if hours < 1
        hours == 1 ? "in an hour" : "in #{hours} hours"
      end

      # 24h clock, with the two round-hour words the owner called out.
      def clock(time)
        return "noon"     if time.hour == 12 && time.min.zero?
        return "midnight" if time.hour.zero? && time.min.zero?

        format("%02d:%02d", time.hour, time.min)
      end

      def year_suffix(time, ref)
        time.year == ref.year ? "" : " #{time.year}"
      end

      # English ordinal day: 1st, 2nd, 3rd, 4th … 21st, 22nd, 23rd … 31st.
      ORDINAL_SUFFIX = { 1 => "st", 2 => "nd", 3 => "rd", 21 => "st", 22 => "nd", 23 => "rd", 31 => "st" }.freeze

      def ordinal(day)
        "#{day}#{ORDINAL_SUFFIX.fetch(day, 'th')}"
      end
    end
  end
end
