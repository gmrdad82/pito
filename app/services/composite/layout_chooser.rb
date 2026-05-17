# Phase 14 §2 + Phase 27 §02 — Composite layout chooser.
#
# Given a positive integer member count, returns the layout class
# that produces the 300×400 composite for that many tiles. One
# distinct layout per N up to the 9-cap, then the overflow variant:
#
#   1     → Composite::Layout::Single
#   2     → Composite::Layout::Pair
#   3     → Composite::Layout::Netflix
#   4     → Composite::Layout::Quad
#   5     → Composite::Layout::Netflix5
#   6     → Composite::Layout::SixGrid
#   7     → Composite::Layout::Netflix7
#   8     → Composite::Layout::EightGrid
#   9     → Composite::Layout::NineGrid
#   10..  → Composite::Layout::NineGridWithOverflow
#
# 0 / negative / non-integer raise ArgumentError.
module Composite
  module LayoutChooser
    module_function

    def choose(count)
      raise ArgumentError, "count must be an integer" unless count.is_a?(Integer)
      raise ArgumentError, "count must be positive (got #{count})" if count <= 0

      case count
      when 1 then Composite::Layout::Single
      when 2 then Composite::Layout::Pair
      when 3 then Composite::Layout::Netflix
      when 4 then Composite::Layout::Quad
      when 5 then Composite::Layout::Netflix5
      when 6 then Composite::Layout::SixGrid
      when 7 then Composite::Layout::Netflix7
      when 8 then Composite::Layout::EightGrid
      when 9 then Composite::Layout::NineGrid
      else        Composite::Layout::NineGridWithOverflow
      end
    end
  end
end
