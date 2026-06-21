# frozen_string_literal: true

module Pito
  module Analytics
    # A single analytics scalar rendered as a bare number, colored by its trend
    # vs the previous comparable interval — no arrow glyphs. A rising value
    # shimmers green upward, a falling value shimmers red downward, a steady value
    # stays the default foreground.
    #
    # Trend states (4): :up, :down, :steady, :neutral.
    #   - :neutral — no comparison possible: a `lifetime` window (comparable:
    #     false) or no value at all. Plain foreground, no shimmer.
    #   - growth from nothing — in a comparable window whose previous value is nil
    #     or zero (e.g. a just-released video's "previous month"), a positive
    #     current counts as :up.
    #
    # Polarity: for metrics where more is worse (dislikes, subs lost) pass
    # `higher_is_better: false` — the visual up/down is then inverted (a numeric
    # rise reads red-down, a numeric fall reads green-up). Steady/neutral are
    # unaffected.
    #
    # kwargs:
    #   value:            (Numeric, nil) current value — displayed + drives trend.
    #   previous:         (Numeric, nil) prior comparable value (nil = none yet).
    #   comparable:       (Boolean) false for lifetime (no trend possible).
    #   higher_is_better: (Boolean) metric polarity; false for dislikes/subs_lost.
    #   display:          (String, nil) optional pre-formatted display string;
    #                     defaults to Pito::Formatter::CompactCount of `value`.
    class TrendNumberComponent < ViewComponent::Base
      def initialize(value:, previous: nil, comparable: true, higher_is_better: true, display: nil)
        @value            = value
        @previous         = previous
        @comparable       = comparable
        @higher_is_better = higher_is_better
        @display          = display
      end

      def call
        tag.span(display_value, class: css_class, data: { trend: trend })
      end

      # One of :up, :down, :steady, :neutral (polarity already applied).
      def trend
        @trend ||= resolve_trend
      end

      private

      def resolve_trend
        return :neutral unless @comparable   # lifetime → no possible baseline
        return :neutral if @value.nil?       # nothing to show

        with_polarity(numeric_direction)
      end

      def numeric_direction
        direction = Pito::Analytics::Trend.for(current: @value, previous: @previous)
        return direction unless direction == :none

        # Comparable window but no (or zero) prior value → growth from nothing.
        @value.to_f.positive? ? :up : :neutral
      end

      def with_polarity(direction)
        return direction if @higher_is_better

        case direction
        when :up   then :down
        when :down then :up
        else            direction
        end
      end

      def display_value
        @display || Pito::Formatter::CompactCount.call(@value)
      end

      def css_class
        base = "pito-trend-number"
        case trend
        when :up   then "#{base} #{base}--up"
        when :down then "#{base} #{base}--down"
        else            base
        end
      end
    end
  end
end
