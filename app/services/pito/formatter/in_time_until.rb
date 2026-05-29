# Pure function. Renders a future Date / Time value as a compact
# "in Nd" / "in Nw" string from now's vantage point.
#
# Sibling of `Pito::Formatter::CompactTimeAgo` (the past-tense
# counterpart). Kept in a separate module so each function has a
# single, predictable rule set — `CompactTimeAgo` clamps the future
# to `~0s ago` (correct for its surface: "what's the last sync time"
# is always in the past). This module clamps the past to `today`
# instead, since its surface (upcoming-game shelves, calendar countdowns)
# is the inverse.
#
# Rounding rule: same floor-towards-zero / integer-division as
# `CompactTimeAgo`. A release 13 days out reads `in 1w`, not
# `in 2w`. A release 6 days out reads `in 6d`, not `in 1w`.
#
# Examples (assuming today = 2026-05-25):
#   nil                            => "unknown"
#   2026-05-25  (today)            => "today"
#   2026-05-26  (1 day  out)       => "in 1d"
#   2026-05-31  (6 days out)       => "in 6d"
#   2026-06-01  (1 week out)       => "in 1w"
#   2026-06-15  (3 weeks out)      => "in 3w"
#   2026-07-25  (~2 months out)    => "in 2mo"
#   2027-05-25  (1 year out)       => "in 1yr"
#   2026-05-20  (5 days past)      => "today"  (clamped)
#
# Pure function — accepts either a Date or a Time / DateTime. Returns
# a `String`. No I/O, no Rails-specific calls beyond `Date.current` /
# `Time.current` which the consumer's Time-zone-aware Rails env
# resolves correctly.
module Pito
  module Formatter
    module InTimeUntil
      module_function

      def call(value)
        return "unknown" if value.nil?

        target_date = value.respond_to?(:to_date) ? value.to_date : value
        delta_days  = (target_date - Date.current).to_i
        return "today" if delta_days <= 0

        return "in #{delta_days}d" if delta_days < 7
        return "in #{delta_days / 7}w" if delta_days < 30
        return "in #{delta_days / 30}mo" if delta_days < 365

        "in #{delta_days / 365}yr"
      end
    end
  end
end
