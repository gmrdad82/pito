# frozen_string_literal: true

module Pito
  module Detail
    # The shared two-column detail-card SHELL used by the channel / video / game
    # detail cards (was copy-pasted in all three templates).
    #
    # Owns the invariant structure:
    #   LEFT  — intro (with the data-pito-ts-slot timestamp anchor), the image
    #           slot, a hairline, then the Stats/Shinies kv-grid
    #           (.pito-detail-stats);
    #   then the mobile-only column divider;
    #   RIGHT — the body slot inside the flexed right column.
    #
    # What varies stays with the caller:
    #   bem:                  the card's BEM block ("pito-channel-detail", …) —
    #                         these classes are hand-authored in application.css,
    #                         not JIT utilities, so interpolation is purge-safe.
    #   image slot:           the full image box incl. its bespoke wrapper div
    #                         (__banner / __thumbnail / __cover).
    #   body slot:            the whole right-column content (kv rows, bars, …).
    #   right_gap:            right column gap utility ("gap-1" or "gap-2").
    #   stat_counter_metrics: rows for Pito::Stats::CountersComponent.
    #   shinies:              top-per-metric Achievements (badge row omitted
    #                         when empty).
    class CardComponent < ViewComponent::Base
      renders_one :image
      renders_one :body

      def initialize(bem:, stat_counter_metrics:, shinies: [], intro: nil, right_gap: "gap-1")
        @bem                  = bem
        @stat_counter_metrics = stat_counter_metrics
        @shinies              = shinies
        @intro                = intro
        @right_gap            = right_gap
      end

      attr_reader :bem, :stat_counter_metrics, :shinies, :intro, :right_gap
    end
  end
end
