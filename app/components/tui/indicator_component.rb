module Tui
  # Beta 4 — Phase F2. TUI activity indicator primitive. Renders one
  # of two shape-driven variants per ADR 0016 visual conventions:
  #
  #   :bounce_equals -> 6-frame `=---` / `-=--` / `--=-` / `---=` /
  #                     `--=-` / `-=--`. ROW / LINE / HORIZONTAL
  #                     contexts (>~10ch wide); reads as a slider
  #                     bouncing across a track.
  #   :braille       -> 10-frame `⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏`. SQUARE /
  #                     RECTANGLE / BOX / CELL / SMALL-SPACE contexts
  #                     (1 char wide); reads as a 1-char dot spinner.
  #
  # Four modes drive the rendered state:
  #
  #   :idle          -> no animation, neutral / Dracula green color
  #                     (steady, "ready"). The initial frame is
  #                     rendered statically so SSR is meaningful even
  #                     without JS hydration.
  #   :indeterminate -> animated spinner; Stimulus controller advances
  #                     frames at the variant cadence (120ms bounce,
  #                     100ms braille). Color: Dracula orange (amber)
  #                     to signal transient work.
  #   :progress      -> static ASCII bar `[▓▓▓░░░] N/M`. No animation
  #                     — the bar IS the signal. Width 8, clamped 0..8.
  #                     Color: Dracula orange.
  #   :error         -> static red ✗. No animation. Color: danger.
  #
  # `start_offset:` lets multiple instances on the same page de-sync
  # so a screen full of spinners doesn't beat in unison. The Stimulus
  # controller seeds its frame index from this offset modulo
  # frames.length on connect().
  #
  # ADR 0017 (cable-first architecture) maps payload kinds to indicator
  # state — consumers thread that mapping; this component is the
  # pure presentational primitive.
  class IndicatorComponent < ViewComponent::Base
    VARIANTS = %i[bounce_equals braille].freeze
    MODES = %i[idle indeterminate progress error].freeze

    BOUNCE_EQUALS_FRAMES = [ "=---", "-=--", "--=-", "---=", "--=-", "-=--" ].freeze
    BRAILLE_FRAMES = [ "⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏" ].freeze

    PROGRESS_BAR_WIDTH = 8

    def initialize(variant:, mode: :indeterminate, start_offset: 0, progress_current: nil, progress_total: nil)
      @variant = variant.to_sym
      @mode = mode.to_sym
      @start_offset = start_offset.to_i
      @progress_current = progress_current
      @progress_total = progress_total

      raise ArgumentError, "unknown variant #{variant}" unless VARIANTS.include?(@variant)
      raise ArgumentError, "unknown mode #{mode}" unless MODES.include?(@mode)
    end

    attr_reader :variant, :mode, :start_offset, :progress_current, :progress_total

    def frames
      case variant
      when :bounce_equals then BOUNCE_EQUALS_FRAMES
      when :braille then BRAILLE_FRAMES
      end
    end

    def css_class
      "tui-indicator tui-indicator--#{variant} tui-indicator--#{mode}"
    end

    def progress_bar
      return nil unless mode == :progress && progress_total.to_i.positive?

      width = PROGRESS_BAR_WIDTH
      filled = ((progress_current.to_f / progress_total.to_f) * width).round.clamp(0, width)
      empty = width - filled
      "[#{"▓" * filled}#{"░" * empty}]"
    end

    def progress_label
      return nil unless mode == :progress
      return nil if progress_current.nil? || progress_total.nil?
      "#{progress_current}/#{progress_total}"
    end

    def initial_frame
      idx = start_offset % frames.length
      frames[idx]
    end
  end
end
