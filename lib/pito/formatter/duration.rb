# frozen_string_literal: true

# Pure function. Human-readable formatter for a duration in seconds.
#
# Input: duration in seconds (Integer, Float, or nil).
# Output: "DD:HH:MM:SS" with leading zero-units trimmed; minimum granularity
# is M:SS. Inner units are zero-padded to 2 digits; seconds are always shown.
#
# Nil and negative values return nil so callers can decide how to render them.
#
# Examples:
#   call(nil)    => nil
#   call(-5)     => nil
#   call(0)      => "0:00"
#   call(34)     => "0:34"
#   call(574)    => "9:34"
#   call(2603)   => "43:23"
#   call(7200)   => "2:00:00"
#   call(3742)   => "1:02:22"
#   call(3632)   => "1:00:32"
#   call(93909)  => "1:02:05:09"
#   call(86400)  => "1:00:00:00"
module Pito
  module Formatter
    module Duration
      module_function

      def call(seconds)
        return nil unless seconds.present? && seconds >= 0

        secs    = seconds.to_i
        days    = secs / 86_400
        hours   = (secs % 86_400) / 3_600
        minutes = (secs % 3_600) / 60
        s       = secs % 60

        if days.positive?
          format("%d:%02d:%02d:%02d", days, hours, minutes, s)
        elsif hours.positive?
          format("%d:%02d:%02d", hours, minutes, s)
        else
          format("%d:%02d", minutes, s)
        end
      end
    end
  end
end
