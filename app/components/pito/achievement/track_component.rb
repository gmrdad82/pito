# frozen_string_literal: true

module Pito
  module Achievement
    # Renders a full-width responsive milestone progress track.
    #
    # Layout — a label block above a flex rail that spans the full message width:
    #
    #   Subs
    #   ●───────●───────●───────●───────◉───────○───────○  …  ○
    #   1       2       5       10      20      50      100  …  10M
    #
    # The rail is a flex row of 22 cell columns (dot stacked above its value
    # label), separated by flex-grow connector spans.  Connectors stretch to fill
    # available width automatically — no JS.  When the sidebar opens or closes the
    # container reflows and the connectors re-stretch; behaviour is purely CSS.
    #
    # Glyph rules per threshold t:
    #   ●  — reached (t ≤ current_value) but not the highest reached milestone.
    #   ◉  — the highest reached milestone (current standing).
    #   ○  — not yet reached (t > current_value), or all when current_value < 1.
    #
    # Dot colors: the whole *reached run* — every reached dot plus the connectors
    # between them, up to and including the standing ◉ — shimmers (background-clip
    # text gradient, shared `pito-kbd-shimmer-sweep` keyframe) coloured by the
    # NEXT unreached tier (not each dot's own tier). The next-tier token is set as
    # `data-accent` on the reached-run elements so `currentColor` resolves to that
    # colour; if the top tier is already reached we fall back to the highest tier.
    # Each reached element gets a shared `Pito::Shimmer.offset_class` stagger so
    # the run doesn't pulse as one flat block. Upcoming dots/connectors stay dim
    # and static (pito-achievement-track__dot--upcoming).
    #
    # kwargs:
    #   label:         (String)  — already title-case metric name (rendered as-is).
    #   current_value: (Integer ≥ 0) — lifetime value for this metric.
    class TrackComponent < ViewComponent::Base
      # Long connector fill — clipped by CSS overflow:hidden to available width.
      CONNECTOR_FILL = ("─" * 60).freeze

      def initialize(label:, current_value:)
        @label         = label
        @current_value = current_value
      end

      def call
        tag.span(class: "pito-achievement-track") do
          safe_join([ label_span, rail_span ])
        end
      end

      private

      def label_span
        tag.span(h(@label), class: "pito-achievement-track__label")
      end

      # Flex row: cell — connector — cell — connector — … — cell
      def rail_span
        tag.span(class: "pito-achievement-track__rail") do
          parts = []
          last_idx = Pito::Achievement::Tier::SERIES.length - 1
          Pito::Achievement::Tier::SERIES.each_with_index do |threshold, i|
            parts << cell_span(threshold)
            # The connector after cell i joins cell i+1; it is part of the reached
            # run when its right endpoint is reached (reached is always a prefix).
            parts << connector_span(Pito::Achievement::Tier::SERIES[i + 1]) unless i == last_idx
          end
          safe_join(parts)
        end
      end

      # One column: dot glyph above CompactCount value label.
      def cell_span(threshold)
        tag.span(class: "pito-achievement-track__cell") do
          safe_join([
            dot_span(threshold),
            tag.span(Pito::Formatter::CompactCount.call(threshold),
                     class: "pito-achievement-track__value")
          ])
        end
      end

      def dot_span(threshold)
        glyph = glyph_for(threshold)
        if reached?(threshold)
          tag.span(glyph,
                   class: [ "pito-achievement-track__dot",
                            "pito-achievement-track__dot--reached",
                            Pito::Shimmer.offset_class("dot-#{threshold}") ].join(" "),
                   data: { accent: next_tier_token })
        else
          tag.span(glyph, class: "pito-achievement-track__dot pito-achievement-track__dot--upcoming")
        end
      end

      # +right_threshold+ is the threshold of the cell this connector joins to.
      # nil for the trailing edge (handled by the caller, which never emits one).
      def connector_span(right_threshold)
        if right_threshold && (reached?(right_threshold) || right_threshold == next_threshold)
          tag.span(CONNECTOR_FILL,
                   class: [ "pito-achievement-track__connector",
                            "pito-achievement-track__connector--reached",
                            Pito::Shimmer.offset_class("connector-#{right_threshold}") ].join(" "),
                   data: { accent: next_tier_token })
        else
          tag.span(CONNECTOR_FILL, class: "pito-achievement-track__connector")
        end
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

      # Tier token of the NEXT unreached milestone — the colour the whole reached
      # run shimmers in. Falls back to the highest tier when the top is reached.
      def next_tier_token
        @next_tier_token ||= Pito::Achievement::Tier.token_for(next_threshold)
      end

      # First SERIES threshold strictly greater than the current value; the last
      # (highest) threshold when every milestone is already reached.
      def next_threshold
        @next_threshold ||=
          Pito::Achievement::Tier::SERIES.find { |t| t > @current_value } ||
          Pito::Achievement::Tier::SERIES.last
      end
    end
  end
end
