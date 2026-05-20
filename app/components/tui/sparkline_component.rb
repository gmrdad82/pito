module Tui
  # Beta 4 — Phase F2. TUI sparkline primitive. Renders a mini bar
  # chart inline via Unicode block characters (U+2581..U+2587). The
  # 7-block palette `▁▂▃▄▅▆▇` maps each input value linearly to a
  # height bucket against the series maximum.
  #
  # Pure presentational primitive — no axes, no labels, no JS. The
  # consumer composes it inside table cells, status-bar segments,
  # tile metadata strips. Empty input renders to the empty string;
  # an all-zero series renders as a flat row of the shortest block
  # (`▁`) so the visual width stays predictable.
  #
  # Per ADR 0016 (TUI design system), sparkline color follows the
  # ambient text token so it inherits whatever container it's
  # dropped into; consumers wanting accent color override via the
  # surrounding rule, not via component args.
  class SparklineComponent < ViewComponent::Base
    BLOCKS = %w[▁ ▂ ▃ ▄ ▅ ▆ ▇].freeze

    def initialize(values:)
      @values = values.to_a
    end

    attr_reader :values

    def rendered
      return "" if values.empty?
      max = values.max.to_f
      return BLOCKS.first * values.length if max.zero?
      values.map { |v| BLOCKS[((v / max) * (BLOCKS.length - 1)).round.clamp(0, BLOCKS.length - 1)] }.join
    end
  end
end
