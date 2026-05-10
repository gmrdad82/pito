# Phase 14 §2 — Composite layout chooser.
#
# Given a positive integer member count, returns the layout class
# that produces the 600×800 composite for that many tiles. Five
# templates per Note 4: 1 / 2 / 3 / 4 / 5-9 / 10+.
#
#   1     → Composite::Layout::Single
#   2     → Composite::Layout::Pair
#   3     → Composite::Layout::Netflix
#   4     → Composite::Layout::Quad
#   5..9  → Composite::Layout::NineGrid
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
      when 1     then Composite::Layout::Single
      when 2     then Composite::Layout::Pair
      when 3     then Composite::Layout::Netflix
      when 4     then Composite::Layout::Quad
      when 5..9  then Composite::Layout::NineGrid
      else            Composite::Layout::NineGridWithOverflow
      end
    end
  end
end
