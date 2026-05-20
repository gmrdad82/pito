module Tui
  class ShadedDensityComponent < ViewComponent::Base
    BLOCKS = %w[░ ▒ ▓ █].freeze

    # percent: 0..100
    # width:   number of cells (default 8)
    def initialize(percent:, width: 8)
      @percent = percent.to_f.clamp(0, 100)
      @width = width
    end

    def cells
      # Uniform fill: fully-covered cells render solid █, only the boundary
      # cell shows a sub-step (░ / ▒ / ▓).
      # Each cell has 3 sub-fill steps. Total resolution = 3 * width sub-units.
      # Example: percent=100  width=8 → ████████
      # Example: percent=87.5 width=8 → ███████░
      # Example: percent=50   width=8 → ████░░░░
      total_units = @width * 3
      filled_units = (@percent / 100.0 * total_units).round
      (1..@width).map do |i|
        cell_start = (i - 1) * 3
        cell_end = i * 3
        if filled_units >= cell_end
          BLOCKS[3]              # █ — fully filled cell
        elsif filled_units <= cell_start
          BLOCKS[0]              # ░ — empty cell
        else
          BLOCKS[filled_units - cell_start]  # ▒ (1) or ▓ (2)
        end
      end
    end
  end
end
