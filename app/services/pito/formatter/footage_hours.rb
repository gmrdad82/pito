# frozen_string_literal: true

require "bigdecimal"

# Pure function. Footage-hours formatter for the `games.footage_hours` column.
#
# Input: footage in hours (BigDecimal / Numeric or nil). Values are always
# multiples of 0.5 (e.g. 2.5, 11.0, 0.0).
# Output: dense "<N>h" label — whole numbers drop the decimal ("5h"); halves
# keep one decimal ("12.5h").
#
# Nil, zero, and negative values render as "—" so the cell stays present
# without claiming a fake zero. BigDecimal-based so there is no float drift.
#
# Examples:
#   call(nil)                 => "—"
#   call(0)                   => "—"
#   call(BigDecimal("5.0"))   => "5h"
#   call(BigDecimal("12.5"))  => "12.5h"
#   call(BigDecimal("2.5"))   => "2.5h"
module Pito
  module Formatter
    module FootageHours
      EM_DASH = "—"

      module_function

      def call(hours)
        return EM_DASH if hours.nil?

        value = BigDecimal(hours.to_s)
        return EM_DASH if value <= 0

        if value == value.to_i
          "#{value.to_i}h"
        else
          "#{value.to_s('F')}h"
        end
      end
    end
  end
end
