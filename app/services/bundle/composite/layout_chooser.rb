# Phase 14 §2 + Phase 27 §02 — Bundle::Composite layout chooser.
#
# Given a positive integer member count, returns the layout class
# that produces the 300×400 composite for that many tiles. One
# distinct layout per N up to the 9-cap, then the overflow variant:
#
#   1     → Bundle::Composite::Layout::Single
#   2     → Bundle::Composite::Layout::Pair
#   3     → Bundle::Composite::Layout::Netflix
#   4     → Bundle::Composite::Layout::Quad
#   5     → Bundle::Composite::Layout::Netflix5
#   6     → Bundle::Composite::Layout::SixGrid
#   7     → Bundle::Composite::Layout::Netflix7
#   8     → Bundle::Composite::Layout::EightGrid
#   9     → Bundle::Composite::Layout::NineGrid
#   10..  → Bundle::Composite::Layout::NineGridWithOverflow
#
# 0 / negative / non-integer raise ArgumentError.
class Bundle
  module Composite
    module LayoutChooser
      module_function

      def choose(count)
        raise ArgumentError, "count must be an integer" unless count.is_a?(Integer)
        raise ArgumentError, "count must be positive (got #{count})" if count <= 0

        case count
        when 1 then Bundle::Composite::Layout::Single
        when 2 then Bundle::Composite::Layout::Pair
        when 3 then Bundle::Composite::Layout::Netflix
        when 4 then Bundle::Composite::Layout::Quad
        when 5 then Bundle::Composite::Layout::Netflix5
        when 6 then Bundle::Composite::Layout::SixGrid
        when 7 then Bundle::Composite::Layout::Netflix7
        when 8 then Bundle::Composite::Layout::EightGrid
        when 9 then Bundle::Composite::Layout::NineGrid
        else        Bundle::Composite::Layout::NineGridWithOverflow
        end
      end
    end
  end
end
