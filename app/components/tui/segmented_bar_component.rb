module Tui
  class SegmentedBarComponent < ViewComponent::Base
    FILLED = "▰"
    EMPTY  = "▱"

    # percent: 0..100
    # segments: number of cells (default 10)
    def initialize(percent:, segments: 10)
      @percent = percent.to_f.clamp(0, 100)
      @segments = segments.to_i.clamp(1, 100)
    end

    def cells
      filled_count = (@percent / 100.0 * @segments).round.clamp(0, @segments)
      (FILLED * filled_count) + (EMPTY * (@segments - filled_count))
    end
  end
end
