# frozen_string_literal: true

module Pito
  module Achievement
    # Renders an achievement (shiny) badge as a single CSS-bordered rounded box
    # with a highlight that travels around the border perimeter (a rotating
    # conic-gradient ring — see `.pito-achievement-badge` in application.css).
    #
    # All badges share one uniform rounded border regardless of metric (the old
    # per-metric box-drawing charsets are gone — they rendered at != 1ch on
    # mobile and the right border drifted). A min-width keeps a column/row of
    # badges aligned; the content is centered.
    #
    # Content (centered): "<value> <ABBR> · <Mon 'YY>", e.g. "1K S · Aug '26".
    #   - value: Pito::Formatter::CompactCount.call(threshold), tier-coloured.
    #   - abbr:  Pito::Achievements::Label.abbr(metric).
    #   - date:  "· Mon 'YY" in a muted sub-span (--fg-dim), distinct from the
    #            tier-coloured value/border. Omitted entirely when unlocked_on nil.
    #
    # The tier colour (value text + border) is set via data-accent =
    # Pito::Achievement::Tier.token_for(threshold). The perimeter shimmer is
    # staggered across adjacent badges via Pito::Shimmer.offset_class so they
    # never rotate in phase.
    #
    # kwargs:
    #   threshold:   (Integer) — one of the 22 milestone steps.
    #   metric:      (String, Symbol) — achievement metric key.
    #   unlocked_on: (Date, nil) — when present, appends "· Mon 'YY"; nil omits.
    class BadgeComponent < ViewComponent::Base
      def initialize(threshold:, metric:, unlocked_on: nil)
        @threshold   = threshold
        @metric      = metric
        @unlocked_on = unlocked_on
      end

      def call
        tag.span(class: css_classes, data: { accent: accent }) do
          safe_join(content_parts)
        end
      end

      private

      # Stable per-badge stagger bucket so adjacent badges don't rotate in sync.
      def offset_class
        Pito::Shimmer.offset_class("#{@threshold}#{@metric}")
      end

      def css_classes
        "pito-achievement-badge #{offset_class}"
      end

      def accent
        Pito::Achievement::Tier.token_for(@threshold)
      end

      def value
        Pito::Formatter::CompactCount.call(@threshold)
      end

      def content_parts
        abbr  = Pito::Achievements::Label.abbr(@metric)
        parts = [ "#{value} #{abbr}" ]

        if @unlocked_on
          parts << " "
          parts << tag.span(@unlocked_on.strftime("· %b '%y"), class: "pito-achievement-badge__date")
        end

        parts
      end
    end
  end
end
