# frozen_string_literal: true

module Pito
  module Achievement
    # Renders a two-row terminal-style milestone progress track.
    #
    # Example (label: "Subs", current_value: 25):
    #
    #   Subs   ●────●────●────●────◉────○────○────○────○────○────○────○────○────○────○────○────○────○────○────○────○────○
    #          1    2    5    10   20   50   100  200  500  1K   2K   5K   10K  20K  50K  100K 200K 500K 1M   2M   5M   10M
    #
    # Glyph rules per threshold t:
    #   ●  — reached (t ≤ current_value) but not the highest reached milestone.
    #   ◉  — the highest reached milestone (current standing).
    #   ○  — not yet reached (t > current_value), or all when current_value < 1.
    #
    # Dot colors follow the Tier token map (via data-accent on each dot span).
    # Upcoming dots use the pito-achievement-track__dot--upcoming class.
    #
    # Each cell is 5 chars wide (1 dot + 4 connector chars ────), except the
    # last dot which has no trailing connector.  The value row mirrors this
    # width with ljust(5) padding so columns align perfectly in monospace.
    #
    # kwargs:
    #   label:         (String)  — already title-case metric name (rendered as-is).
    #   current_value: (Integer ≥ 0) — lifetime value for this metric.
    class TrackComponent < ViewComponent::Base
      CONNECTOR = "────"

      def initialize(label:, current_value:)
        @label         = label
        @current_value = current_value
      end

      def call
        tag.span(class: "pito-achievement-track") do
          safe_join([ dot_row, "\n", value_row ])
        end
      end

      private

      # Row 1: label + 3 spaces + one span per dot, connectors between dots.
      def dot_row
        parts = [ safe_join([ h(@label), "   " ]) ]
        last_idx = Pito::Achievement::Tier::SERIES.length - 1
        Pito::Achievement::Tier::SERIES.each_with_index do |threshold, i|
          parts << dot_span(threshold)
          parts << connector_span unless i == last_idx
        end
        safe_join(parts)
      end

      # Row 2: gutter of spaces (same width as label + 3) + CompactCount labels,
      # each left-aligned in a 5-char cell (matching dot+connector width).
      def value_row
        gutter = " " * (@label.length + 3)
        parts = [ gutter ]
        last_idx = Pito::Achievement::Tier::SERIES.length - 1
        Pito::Achievement::Tier::SERIES.each_with_index do |threshold, i|
          cell = Pito::Formatter::CompactCount.call(threshold)
          cell = cell.ljust(5) unless i == last_idx
          parts << tag.span(cell, class: "pito-achievement-track__value")
        end
        safe_join(parts)
      end

      def dot_span(threshold)
        glyph = glyph_for(threshold)
        if reached?(threshold)
          tag.span(glyph,
                   class: "pito-achievement-track__dot",
                   data: { accent: Pito::Achievement::Tier.token_for(threshold) })
        else
          tag.span(glyph, class: "pito-achievement-track__dot pito-achievement-track__dot--upcoming")
        end
      end

      def connector_span
        tag.span(CONNECTOR, class: "pito-achievement-track__connector")
      end

      def glyph_for(threshold)
        return "○" unless reached?(threshold)

        threshold == highest_reached ? "◉" : "●"
      end

      # A threshold is "reached" when the entity's current value meets or exceeds it.
      def reached?(threshold)
        @current_value >= 1 && threshold <= @current_value
      end

      # The last (highest) threshold in SERIES that has been reached.
      # Memoised; only called when current_value ≥ 1.
      def highest_reached
        @highest_reached ||= Pito::Achievement::Tier::SERIES.select { |t| t <= @current_value }.last
      end
    end
  end
end
