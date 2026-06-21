# frozen_string_literal: true

module Pito
  module Achievement
    # Renders a fixed-width terminal-style achievement badge using box-drawing
    # characters.  All badges share the same outer width regardless of content,
    # so a column of badges aligns perfectly in a monospace context.  The inner
    # content is centered within the box.
    #
    # Each metric gets a distinct border charset so the metric is recognizable
    # by its border at a glance — tier color (via data-accent) is driven by
    # threshold and remains unchanged.
    #
    # Example (threshold: 1_000, metric: :subs, unlocked_on: Date.new(2026,8,1)):
    #   ╔════════════════════╗
    #   ║    1K S · Aug '26  ║
    #   ╚════════════════════╝
    #
    # kwargs:
    #   threshold:   (Integer) — one of the 22 milestone steps.
    #   metric:      (String, Symbol) — achievement metric key; the badge
    #                derives its single-letter abbreviation via
    #                Pito::Achievements::Label.abbr(metric) and its border
    #                charset from BORDERS.
    #   unlocked_on: (Date, nil) — when present, appends "· Mon 'YY" in a
    #                muted span; when nil the date is omitted entirely.
    class BadgeComponent < ViewComponent::Base
      # Inner content area width (chars). Sized for the longest realistic
      # content: "500K W · Jun '26" = 16 chars, centered within 18 (so even the
      # longest keeps ~1 space each side from centering). No extra explicit
      # padding inside the bars — the box hugs the content tightly.
      # DASH_COUNT == INNER_WIDTH so the top/bottom borders match the middle
      # line (│ + content + │, no padding spaces).
      INNER_WIDTH = 18
      DASH_COUNT  = INNER_WIDTH  # 18

      # Per-metric box-drawing charsets.  Every glyph occupies exactly one
      # monospace cell, so DASH_COUNT * h stays width-invariant across all
      # metrics.  subs and subs_gained share the double-line style — they
      # never appear together on the same entity.
      Border = Data.define(:tl, :tr, :bl, :br, :h, :v)

      BORDERS = {
        "subs"          => Border.new(tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║"),
        "subs_gained"   => Border.new(tl: "╔", tr: "╗", bl: "╚", br: "╝", h: "═", v: "║"),
        "views"         => Border.new(tl: "╭", tr: "╮", bl: "╰", br: "╯", h: "─", v: "│"),
        "watched_hours" => Border.new(tl: "┌", tr: "┐", bl: "└", br: "┘", h: "┈", v: "┊"),
        "likes"         => Border.new(tl: "┌", tr: "┐", bl: "└", br: "┘", h: "╌", v: "╎"),
        "comments"      => Border.new(tl: "┏", tr: "┓", bl: "┗", br: "┛", h: "━", v: "┃")
      }.freeze

      def initialize(threshold:, metric:, unlocked_on: nil)
        @threshold   = threshold
        @metric      = metric
        @unlocked_on = unlocked_on
      end

      def call
        b = border
        tag.span(class: "pito-achievement-badge whitespace-pre", data: { accent: accent }) do
          safe_join([ top_line, "\n#{b.v}", middle_content, "#{b.v}\n", bottom_line ])
        end
      end

      private

      def border
        BORDERS.fetch(@metric.to_s, BORDERS["views"])
      end

      def accent
        Pito::Achievement::Tier.token_for(@threshold)
      end

      def value
        Pito::Formatter::CompactCount.call(@threshold)
      end

      def top_line
        b = border
        b.tl + (b.h * DASH_COUNT) + b.tr
      end

      def bottom_line
        b = border
        b.bl + (b.h * DASH_COUNT) + b.br
      end

      # Builds the inner content of the middle line, centered to INNER_WIDTH.
      # The date (when present) lives in a separate span so CSS can mute its
      # color independently of the tier-colored surrounding text.
      def middle_content
        abbr_str     = Pito::Achievements::Label.abbr(@metric)
        value_str    = value
        base_length  = value_str.length + 1 + abbr_str.length

        if @unlocked_on
          date_str       = @unlocked_on.strftime("· %b '%y")
          content_length = base_length + 1 + date_str.length
          padding        = [ INNER_WIDTH - content_length, 0 ].max
          left_pad       = padding / 2
          right_pad      = padding - left_pad
          safe_join([
            " " * left_pad,
            "#{value_str} #{abbr_str} ",
            tag.span(date_str, class: "pito-achievement-badge__date"),
            " " * right_pad
          ])
        else
          content_length = base_length
          padding        = [ INNER_WIDTH - content_length, 0 ].max
          left_pad       = padding / 2
          right_pad      = padding - left_pad
          safe_join([ " " * left_pad, "#{value_str} #{abbr_str}", " " * right_pad ])
        end
      end
    end
  end
end
