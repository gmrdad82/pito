module Analytics
  # Analytics::LegendSwatchComponent
  #
  # A bracketed legend swatch — colored bracket character(s) + label.
  # Used in chart legends throughout the analytics UI.
  #
  # Replaces the AnalyticsHelper#bracketed_legend helper which used
  # inline style="color: ..." (forbidden per docs/design.md).
  #
  # ## Kwargs
  #
  # @param label [String] visible text
  # @param color [String] CSS color value (token or hex) — passed as
  #   a CSS custom property, NOT inline style
  # @param glyph [String] default "[ ]" — the bracket characters
  #
  # ## Usage
  #
  # <%= render Analytics::LegendSwatchComponent.new(label: "channel 1", color: "var(--accent-videos)") %>
  class LegendSwatchComponent < ViewComponent::Base
    def initialize(label:, color:, glyph: "[ ]")
      @label = label
      @color = color
      @glyph = glyph
    end

    attr_reader :label, :color, :glyph
  end
end
