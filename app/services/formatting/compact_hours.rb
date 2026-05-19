# Phase 37 Wave A1 — `Formatting::CompactHours`.
#
# Pure function. Renders an hour count as a short human-readable string
# with the European `.` thousands separator. Used by the
# `Channels::IdCardComponent` watch-hours row.
#
# Rules (locked 2026-05-19, user):
#
#   nil       → "—" (em-dash)
#   0         → "0h"
#   1..999    → "<n>h"            (e.g. "12h", "47h", "589h")
#   1_000+    → European `.` thousands separator + "h"
#               (e.g. 1_200 → "1.200h", 12_500 → "12.500h",
#                356_323 → "356.323h")
#
# Hours are NEVER K-compressed — user-explicit decision so a 356_323-hour
# watch-time stays readable at exact precision. Pure function — no I/O,
# no I18n, no Rails dependency. The `.` separator is hardcoded (not
# `I18n.t("number.format.delimiter")`).
module Formatting
  module CompactHours
    EM_DASH = "—"

    module_function

    def call(hours)
      return EM_DASH if hours.nil?

      n = hours.to_i
      return "0h" if n.zero?

      "#{insert_dot_thousands(n)}h"
    end

    # Insert a `.` every three digits from the right. Handles negatives
    # by preserving the sign in front of the formatted digit run.
    def insert_dot_thousands(integer)
      sign = integer.negative? ? "-" : ""
      digits = integer.abs.to_s
      grouped = digits.reverse.scan(/\d{1,3}/).join(".").reverse
      "#{sign}#{grouped}"
    end
  end
end
