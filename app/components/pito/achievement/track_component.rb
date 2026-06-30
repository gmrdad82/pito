# frozen_string_literal: true

module Pito
  module Achievement
    # Renders a full-width responsive milestone progress track — COLLAPSED.
    #
    # The full series is 22 thresholds (1, 2, 5, … 10M); rendering every dot reads
    # as noise and crowds mobile. The track therefore shows only the points that
    # matter around the standing milestone, eliding the rest behind a shimmering
    # ellipsis. Owner-locked visible set (J4):
    #
    #   1 (always) → … → prev (if any) → current → next (if any) → … → last (always)
    #
    # where `current` is the standing milestone (highest reached threshold, the
    # ◉), `prev`/`next` are its immediate SERIES neighbours, `1` is the first
    # threshold (always shown) and `last` is the top threshold (10M, always shown).
    #
    # Layout — a label block above a flex rail that spans the full message width:
    #
    #   Subs
    #   ●──────●───────◉───────○  ─···─  ○
    #   1      10      20      50        10M
    #
    # The rail is a flex row of cell columns (dot stacked above its value label)
    # joined by flex-grow spans. Between two consecutive VISIBLE points the joiner
    # is either a normal connector (the points are SERIES-adjacent) or a shimmering
    # ELLIPSIS `─···─` (one or more thresholds were skipped). Connectors/ellipses
    # stretch to fill available width automatically — no JS. When the sidebar opens
    # or closes the container reflows; behaviour is purely CSS.
    #
    # Glyph rules per visible threshold t:
    #   ●  — reached (t ≤ current_value) but not the highest reached milestone.
    #   ◉  — the highest reached milestone (current standing).
    #   ○  — not yet reached (t > current_value), or all when current_value < 1.
    #
    # Dot/connector/ellipsis colors: the whole *reached run* — every reached dot
    # plus the joiners between them, up to and including the standing ◉, plus the
    # in-progress joiner toward `next` — shimmers (background-clip text gradient,
    # shared `pito-action-shimmer-sweep` keyframe) coloured by the NEXT unreached tier
    # (not each dot's own tier). The next-tier token is set as `data-accent` on the
    # reached-run elements so `currentColor` resolves to that colour; if the top
    # tier is already reached we fall back to the highest tier. Each reached element
    # gets a shared `Pito::Shimmer.offset_class` stagger so the run doesn't pulse as
    # one flat block. Upcoming dots/joiners stay dim and static.
    #
    # Edge cases (all handled by the index-set algorithm in #visible_indices):
    #   • current at/near the start — left side collapses, no left ellipsis, `1`
    #     never duplicated.
    #   • current at/near the end — right side collapses, no right ellipsis, `last`
    #     never duplicated, no dangling ellipsis.
    #   • all-reached (≥ 10M) — current == last; shows 1 ─···─ prev last.
    #   • zero reached (current_value < 1) — no standing; shows the minimal
    #     1 ─···─ last form (the next target is `1` itself).
    #   • dedup — a point never appears twice (Set-of-indices guarantees it).
    #
    # kwargs:
    #   label:         (String)  — already title-case metric name (rendered as-is).
    #   current_value: (Integer ≥ 0) — lifetime value for this metric.
    class TrackComponent < ViewComponent::Base
      # Long connector fill — clipped by CSS overflow:hidden to available width.
      CONNECTOR_FILL = ("─" * 60).freeze

      # Elided-gap joiner: a CONTINUOUS light-horizontal rule with three middots
      # at its centre. The string is deliberately over-long and gets clipped by
      # CSS (overflow:hidden + text-align:center on .pito-achievement-track__ellipsis)
      # so the dashes fill the WHOLE gap edge-to-edge on both sides of the middots
      # — the skip reads as one unbroken rail, not a `─···─` with empty gaps.
      ELLIPSIS_FLANK = ("─" * 30).freeze
      ELLIPSIS_GLYPH = "#{ELLIPSIS_FLANK}···#{ELLIPSIS_FLANK}".freeze

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

      # Flex row over the VISIBLE points only: cell — joiner — cell — … — cell,
      # where the joiner between SERIES-adjacent points is a connector and the
      # joiner across a gap of one-or-more skipped thresholds is an ellipsis.
      def rail_span
        tag.span(class: "pito-achievement-track__rail") do
          parts = []
          idxs = visible_indices
          idxs.each_with_index do |series_idx, pos|
            parts << cell_span(Pito::Achievement::Tier::SERIES[series_idx])
            next_idx = idxs[pos + 1]
            next unless next_idx

            right = Pito::Achievement::Tier::SERIES[next_idx]
            joiner = next_idx - series_idx > 1 ? ellipsis_span(right) : connector_span(right)
            parts << joiner
          end
          safe_join(parts)
        end
      end

      # Indices into SERIES that stay visible after the collapse. Always the first
      # (0) and last threshold; around the standing milestone its prev/current/next
      # neighbours; when nothing is reached, the next target instead. uniq + sort
      # dedups (e.g. prev == 1, next == last) and orders the rail left→right.
      def visible_indices
        @visible_indices ||= begin
          last_idx = Pito::Achievement::Tier::SERIES.length - 1
          idxs = [ 0, last_idx ]
          if standing_index
            idxs << standing_index
            idxs << standing_index - 1 if standing_index.positive?
            idxs << standing_index + 1 if standing_index < last_idx
          else
            idxs << next_index
          end
          idxs.uniq.sort
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
      # Part of the reached run when its right endpoint is reached (reached is
      # always a prefix) or it is the in-progress joiner toward `next`.
      def connector_span(right_threshold)
        if reached_joiner?(right_threshold)
          tag.span(CONNECTOR_FILL,
                   class: [ "pito-achievement-track__connector",
                            "pito-achievement-track__connector--reached",
                            Pito::Shimmer.offset_class("connector-#{right_threshold}") ].join(" "),
                   data: { accent: next_tier_token })
        else
          tag.span(CONNECTOR_FILL, class: "pito-achievement-track__connector")
        end
      end

      # Joiner across one-or-more skipped thresholds. Same reached-run colouring as
      # a connector (its right endpoint determines membership) but rendered as the
      # short shimmering ellipsis glyph instead of the stretch fill.
      def ellipsis_span(right_threshold)
        if reached_joiner?(right_threshold)
          tag.span(ELLIPSIS_GLYPH,
                   class: [ "pito-achievement-track__ellipsis",
                            "pito-achievement-track__ellipsis--reached",
                            Pito::Shimmer.offset_class("ellipsis-#{right_threshold}") ].join(" "),
                   data: { accent: next_tier_token })
        else
          tag.span(ELLIPSIS_GLYPH, class: "pito-achievement-track__ellipsis")
        end
      end

      # A joiner belongs to the reached run when the cell on its right is reached,
      # or when that cell is the next milestone (the in-progress segment past ◉).
      def reached_joiner?(right_threshold)
        reached?(right_threshold) || right_threshold == next_threshold
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

      # SERIES index of the standing milestone (the ◉), or nil when nothing is
      # reached (current_value < 1) — in which case there is no current dot.
      def standing_index
        return @standing_index if defined?(@standing_index)

        @standing_index = (Pito::Achievement::Tier::SERIES.index(highest_reached) if @current_value >= 1)
      end

      # SERIES index of the next (first unreached) milestone.
      def next_index
        @next_index ||= Pito::Achievement::Tier::SERIES.index(next_threshold)
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
