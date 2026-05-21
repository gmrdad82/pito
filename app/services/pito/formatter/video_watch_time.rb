# Pure function. Renders a watch-time in minutes as a compact "Xh"
# label (whole hours, with thousands delimiter).
#
# Used by video index / show pages for the total watch-time cells.
# Returns "—" for nil or non-positive values.
#
# Examples:
#   nil     => "—"
#   0       => "—"
#   90      => "2h"
#   1500    => "25h"
#   100_000 => "1,667h"
#
# Depends on ActionView::Helpers::NumberHelper (number_with_delimiter)
# via the Rails helper environment. Callers in a non-helper context
# can substitute their own thousands formatter.
module Pito
  module Formatter
    module VideoWatchTime
      EM_DASH = "—"

      module_function

      def call(minutes)
        return EM_DASH unless minutes&.positive?

        hours = (minutes / 60.0).round
        hours_str = hours.to_s.reverse.gsub(/(\d{3})(?=\d)/, '\1,').reverse
        "#{hours_str}h"
      end
    end
  end
end
