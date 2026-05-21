# Pure function. Whole-hour formatter for IGDB time-to-beat fields.
#
# Input: IGDB TTB duration in seconds (Integer or nil).
# Output: dense "<N>h" label (no decimals, no minutes).
#
# Nil, zero, and negative values render as "—" so the cell stays
# present without claiming a fake zero. Rounding uses half-up so values
# just below a whole hour still surface (e.g. 3540s (59m) rounds to 1h).
#
# Examples:
#   call(nil)    => "—"
#   call(0)      => "—"
#   call(-1)     => "—"
#   call(3540)   => "1h"
#   call(7200)   => "2h"
#   call(36000)  => "10h"
module Pito
  module Formatter
    module TtbHours
      EM_DASH = "—"

      module_function

      def call(seconds)
        return EM_DASH if seconds.nil? || seconds.to_i <= 0

        hours = (seconds.to_f / 3_600).round
        "#{hours}h"
      end
    end
  end
end
