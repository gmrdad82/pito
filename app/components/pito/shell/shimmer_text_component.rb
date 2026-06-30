# frozen_string_literal: true

module Pito
  module Shell
    # Renders a shimmering text span (or other inline element) using the
    # existing `.pito-network-shimmer` CSS class — no new keyframes.
    #
    # API:
    #   ShimmerTextComponent.new(text:)
    #     → <span class="pito-network-shimmer">text</span>
    #
    #   ShimmerTextComponent.new(text: ". " * 15, extra_classes: "shrink-0")
    #     → <span class="pito-network-shimmer shrink-0">. . . . . . . . . . . . . . .</span>
    #
    #   ShimmerTextComponent.new(text: "●", extra_classes: "shrink-0", delay: "0.30s")
    #     → <span class="pito-network-shimmer shrink-0" style="animation-delay:0.30s">●</span>
    #
    # Stagger approach: the caller passes an explicit `delay:` string (e.g. "0.15s").
    # This maps to an inline `animation-delay` style. JS-set inline delay on
    # dynamically-rendered step rows is the existing established pattern
    # (see games_search_controller.js STEP_DELAYS); this component provides the
    # same escape hatch for server-rendered rows.
    class ShimmerTextComponent < ViewComponent::Base
      # @param text          [String]       the text inside the shimmer span
      # @param extra_classes [String, nil]  additional Tailwind/utility classes
      # @param delay         [String, nil]  CSS animation-delay value (e.g. "0.30s")
      #                                     for staggered multi-row shimmer
      def initialize(text:, extra_classes: nil, delay: nil)
        @text          = text
        @extra_classes = extra_classes.presence
        @delay         = delay.presence
      end

      attr_reader :text, :extra_classes, :delay

      def css_classes
        [ "pito-network-shimmer", extra_classes ].compact.join(" ")
      end

      def inline_style
        return nil unless delay

        "animation-delay:#{delay}"
      end
    end
  end
end
