# Phase 14 §2 + Phase 27 §02 + 2026-05-25 simplification —
# Bundle::Composite layout chooser.
#
# Given a positive integer member count, returns the layout class
# that produces the 300×400 composite for that many tiles. Four
# supported layouts:
#
#   1     → Bundle::Composite::Layout::Single
#   2     → Bundle::Composite::Layout::Pair
#   3     → Bundle::Composite::Layout::Netflix (3-up)
#   4+    → Bundle::Composite::Layout::CountOverflow
#            (solid accent-colored rectangle with the count as a
#            centered numeral — no game tiles required)
#
# The following layouts are DEPRECATED and no longer reachable via
# this chooser: Quad, Netflix5, SixGrid, Netflix7, EightGrid,
# NineGrid, NineGridWithOverflow. Their files are retained for
# reference but should not be called from new code.
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
        else        Bundle::Composite::Layout::CountOverflow
        end
      end
    end
  end
end
