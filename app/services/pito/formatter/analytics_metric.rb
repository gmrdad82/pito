# Pure function. Numeric formatter dispatching by analytics metric type.
#
# Types:
#   :count / :integer     — number with delimiter (1,234,567)
#   :duration_seconds     — M:SS or H:MM:SS
#   :ratio / :percentage  — "X.XX%"
#   :money                — "$X.XX"
#   anything else         — value.to_s
#
# Nil values render as "—".
#
# Pure function — no I/O, no Rails number helpers dependency (uses
# plain Ruby format). Callers in helper contexts may delegate to
# ActionView number helpers instead.
module Pito
  module Formatter
    module AnalyticsMetric
      EM_DASH = "—"

      module_function

      def call(value, type:)
        return EM_DASH if value.nil?

        case type
        when :count, :integer
          delimit(value.to_i)
        when :duration_seconds
          duration(value.to_f)
        when :ratio, :percentage
          number = value.to_f
          number *= 100.0 if number.abs <= 1.0
          "#{format('%.2f', number)}%"
        when :money
          "$#{format('%.2f', value.to_f)}"
        else
          value.to_s
        end
      end

      def duration(seconds)
        s = seconds.to_i
        hours   = s / 3_600
        minutes = (s % 3_600) / 60
        secs    = s % 60

        if hours > 0
          format("%d:%02d:%02d", hours, minutes, secs)
        else
          format("%d:%02d", minutes, secs)
        end
      end

      def delimit(integer)
        integer.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
      end
    end
  end
end
