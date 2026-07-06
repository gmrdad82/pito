# frozen_string_literal: true

module Pito
  module Achievement
    # Renders an achievement (shiny) badge as a FILLED material chip — the
    # G127 stones/awards design system (`.pito-shiny` in application.css):
    # fixed theme-agnostic palette, travelling gleam, breathing halo.
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
    #               a muted block span (.pito-shiny__date). No middot
    #               separator — the block layout provides the visual separation.
    #               Omits the date row entirely when unlocked_on is nil.
    #
    # The word is the full title-case badge label from Pito::Achievements::Label.badge
    # (e.g. Subs, Views, Likes, Comments, Watched — not single-letter abbreviations).
    #
    # The material (fill + ink + gleam) is set via data-material =
    # Pito::Achievement::Tier.material_for (G127 stones/awards). The gleam is
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

      def initialize(threshold:, metric:, scope:, unlocked_on: nil, form: :extended)
        @threshold   = threshold
        @metric      = metric
        @scope       = scope.to_s
        @unlocked_on = unlocked_on
        @form        = form
      end

      def call
        tag.span(class: css_classes, data: { material: material }) do
          safe_join(content_parts)
        end
      end

      private

      # Stable per-badge stagger bucket — 20 shinies-specific steps (G128) so
      # a wall of chips never gleams in sync (the shared shimmer offsets only
      # have 8 buckets, which read as synchronized waves on long lanes).
      def offset_class
        "pito-shiny-s#{"#{@threshold}#{@metric}#{@scope}".sum % 20}"
      end

      def css_classes
        # Only the compact form (show channel/vid/game detail cards) gets a
        # modifier — slimmer padding, truncating face; its strip container caps
        # at 3 per row (.pito-detail-card__shinies). The extended form
        # (shinies-verb message) stays on the base class.
        base = "pito-shiny #{offset_class}"
        base += " pito-shiny--iridescent" if %w[pearl opal diamond].include?(material)
        base += " pito-shiny--award" if Pito::Achievement::Tier::AWARDS.value?(material)
        @form == :compact ? "#{base} pito-shiny--compact" : base
      end

      def material
        @material ||= Pito::Achievement::Tier.material_for(
          scope: @scope, metric: @metric, threshold: @threshold
        )
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
                            class: "pito-shiny__date block")
        end

        parts
      end
    end
  end
end
