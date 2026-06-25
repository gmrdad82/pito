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
    # Two display forms via the `form:` kwarg:
    #
    #   :compact  — one line: "<value> <Word>" (e.g. "1K Subs"). No date.
    #   :extended — two lines: row 1 "<value> <Word>", row 2 the unlock date in
    #               a muted block span (.pito-achievement-badge__date). No middot
    #               separator — the block layout provides the visual separation.
    #               Omits the date row entirely when unlocked_on is nil.
    #
    # The word is the full title-case badge label from Pito::Achievements::Label.badge
    # (e.g. Subs, Views, Likes, Comments, Watched — not single-letter abbreviations).
    #
    # The tier colour (value text + border) is set via data-accent =
    # Pito::Achievement::Tier.token_for(threshold). The perimeter shimmer is
    # staggered across adjacent badges via Pito::Shimmer.offset_class so they
    # never rotate in phase.
    #
    # kwargs:
    #   threshold:   (Integer) — one of the 22 milestone steps.
    #   metric:      (String, Symbol) — achievement metric key.
    #   unlocked_on: (Date, nil) — when present and form is :extended, appends
    #                "Mon 'YY" in a muted block span; nil or compact omits it.
    #   form:        (:compact | :extended) — display form; default :extended.
    class BadgeComponent < ViewComponent::Base
      FORMS = %i[compact extended].freeze

      def initialize(threshold:, metric:, unlocked_on: nil, form: :extended)
        @threshold   = threshold
        @metric      = metric
        @unlocked_on = unlocked_on
        @form        = form
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
        # Pluralise the face word by the threshold: "1 Like" (singular) vs
        # "100 Likes" / "1K Subs" (plural). watched_hours' face is invariant.
        word  = Pito::Achievements::Label.badge(@metric, count: @threshold)
        parts = [ "#{value} #{word}" ]

        if @form == :extended && @unlocked_on
          parts << tag.span(@unlocked_on.strftime("%b '%y"),
                            class: "pito-achievement-badge__date block")
        end

        parts
      end
    end
  end
end
