# frozen_string_literal: true

module Pito
  module Achievement
    # Renders a fixed-width terminal-style achievement badge using box-drawing
    # characters. All badges share the same outer width regardless of content,
    # so a column of badges aligns perfectly in a monospace context.
    #
    # Example (threshold: 1_000, label: "Subs", unlocked_on: Date.new(2026,6,20)):
    #   ╭────────────────────────────╮
    #   │ 1K Subs (20-06-2026)       │
    #   ╰────────────────────────────╯
    #
    # kwargs:
    #   threshold:   (Integer) — one of the 22 milestone steps.
    #   label:       (String)  — already title-case metric name, e.g. "Subs".
    #   unlocked_on: (Date, nil) — when present, appends "(dd-mm-yyyy)" in a
    #                muted span; when nil the date is omitted entirely.
    class BadgeComponent < ViewComponent::Base
      # Inner content area width (chars). Sized for the longest realistic
      # content: "500K Watched (20-06-2026)" = 25 chars, plus one char of
      # breathing room → 26.  DASH_COUNT = INNER_WIDTH + 2 (one padding space
      # on each side of the content, matching the ─ run length).
      INNER_WIDTH = 26
      DASH_COUNT  = INNER_WIDTH + 2  # 28

      def initialize(threshold:, label:, unlocked_on: nil)
        @threshold   = threshold
        @label       = label
        @unlocked_on = unlocked_on
      end

      def call
        tag.span(class: "pito-achievement-badge", data: { accent: accent }) do
          safe_join([ top_line, "\n│ ", middle_content, " │\n", bottom_line ])
        end
      end

      private

      def accent
        Pito::Achievement::Tier.token_for(@threshold)
      end

      def value
        Pito::Formatter::CompactCount.call(@threshold)
      end

      def top_line
        "╭" + ("─" * DASH_COUNT) + "╮"
      end

      def bottom_line
        "╰" + ("─" * DASH_COUNT) + "╯"
      end

      # Builds the inner content of the middle line, padded to INNER_WIDTH.
      # The date (when present) lives in a separate span so CSS can mute its
      # color independently of the tier-colored surrounding text.
      def middle_content
        value_str    = value
        # Use the raw label length for character-width calculations; h() only
        # escapes < > & " which the caller's title-case labels never contain.
        base_length  = value_str.length + 1 + @label.length

        if @unlocked_on
          date_str   = @unlocked_on.strftime("(%d-%m-%Y)")
          used_chars = base_length + 1 + date_str.length  # +1 for the space before date
          pad        = " " * [ INNER_WIDTH - used_chars, 0 ].max
          safe_join([ "#{value_str} ", h(@label), " ",
                     tag.span(date_str, class: "pito-achievement-badge__date"),
                     pad ])
        else
          pad = " " * [ INNER_WIDTH - base_length, 0 ].max
          safe_join([ "#{value_str} ", h(@label), pad ])
        end
      end
    end
  end
end
