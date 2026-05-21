# Pure function. Renders a duration in seconds as H:MM:SS or M:SS.
#
# Used by video / footage tables for per-row precision timing.
# Returns "—" for nil or non-positive values.
#
# Examples:
#   nil     => "—"
#   0       => "—"
#   65      => "1:05"
#   3725    => "1:02:05"
module Pito
  module Formatter
    module Duration
      EM_DASH = "—"

      module_function

      def call(seconds)
        return EM_DASH unless seconds&.positive?

        hours = seconds / 3_600
        mins  = (seconds % 3_600) / 60
        secs  = seconds % 60

        if hours > 0
          format("%d:%02d:%02d", hours, mins, secs)
        else
          format("%d:%02d", mins, secs)
        end
      end
    end
  end
end
