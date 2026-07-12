# frozen_string_literal: true

require "bigdecimal"

# Pure function. Footage-hours formatter for the `games.footage_hours` column.
#
# Input: footage in hours (BigDecimal / Numeric or nil). Values are always
# multiples of 0.5 (e.g. 2.5, 11.0, 0.0).
# Output: dense "<N>h" label — whole numbers drop the decimal ("5h"); halves
# keep one decimal ("12.5h").
#
# Footage ALWAYS has 0 as its fallback (games.footage_hours is `default 0, NOT
# NULL`), so nil / zero / negative render as "0h" — never a dash.
# BigDecimal-based so there is no float drift.
#
# Examples:
#   call(nil)                 => "0h"
#   call(0)                   => "0h"
#   call(BigDecimal("5.0"))   => "5h"
#   call(BigDecimal("12.5"))  => "12.5h"
#   call(BigDecimal("2.5"))   => "2.5h"
module Pito
  module Formatter
    module FootageHours
      module_function

      def call(hours)
        value = hours.nil? ? BigDecimal(0) : BigDecimal(hours.to_s)
        value = BigDecimal(0) if value.negative?

        if value == value.to_i
          "#{value.to_i}h"
        else
          "#{value.to_s('F')}h"
        end
      end
    end
  end
end
