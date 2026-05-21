# Pure function. Renders a seconds value as "Xh Ym" or "Ym" or "Yh".
#
# Used by game time-to-beat and similar IGDB duration fields where the
# stored value is in seconds and the display is humanized hours+minutes.
# Returns "—" for nil, non-Integer, or non-positive values.
#
# Examples:
#   nil     => "—"
#   0       => "—"
#   1800    => "30m"
#   3600    => "1h"
#   5400    => "1h 30m"
#   7200    => "2h"
module Pito
  module Formatter
    module Seconds
      EM_DASH = "—"

      module_function

      def call(seconds)
        return EM_DASH unless seconds.is_a?(Integer) && seconds.positive?

        hours   = seconds / 3_600
        minutes = (seconds % 3_600) / 60

        if hours.positive?
          minutes.zero? ? "#{hours}h" : "#{hours}h #{minutes}m"
        else
          "#{minutes}m"
        end
      end
    end
  end
end
