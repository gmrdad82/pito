# Pure function. Zero-pads an IGDB rating to two digits.
#
# The IGDB rating is a decimal in storage (igdb_rating is decimal(5,2)).
# Accepts any numeric and rounds defensively to an integer before padding.
# Returns "" for nil so callers can safely interpolate without conditional
# guards.
#
# Examples:
#   call(nil)    => ""
#   call(5)      => "05"
#   call(93)     => "93"
#   call(100)    => "100"
#   call(8.7)    => "09"
module Pito
  module Formatter
    module GameRating
      module_function

      def call(rating)
        return "" if rating.nil?

        format("%02d", rating.to_i)
      end
    end
  end
end
