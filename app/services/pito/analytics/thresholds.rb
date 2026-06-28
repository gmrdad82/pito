# frozen_string_literal: true

module Pito
  module Analytics
    # Per-metric "health" thresholds that drive each chart's red→green gradient.
    # The threshold is subscriber-aware so a small channel isn't unfairly red.
    #
    # VIEWS (first metric):
    #   target_daily = VIEWS_M × subscribers / 7   (per-WEEK pace — the green line
    #   sits at the same daily height regardless of the chosen period; only the
    #   chart's x-span changes). "Full green" ≈ pulling roughly your subscriber
    #   count in views every week. VIEWS_M is the single tunable difficulty knob.
    #
    # Subscriber basis per level: channel = the channel(s); vid = its channel;
    # game = Σ distinct channels owning the linked vids. subs are READ from
    # Pito::Stats (never mutated here).
    module Thresholds
      VIEWS_M = 1.0  # difficulty multiplier — ONE place to tune "how green is green"
      WEEK    = 7.0

      module_function

      # Daily full-green Views target for a scope of `subs` subscribers.
      def views_target_daily(subs:)
        s = subs.to_i
        return 0.0 if s <= 0

        VIEWS_M * s / WEEK
      end

      # Subscriber basis for the scope (Σ distinct channels' subs).
      # @param level [String, Symbol] :channel | :vid | :game
      # @param entity_ids [Array<Integer>]
      def subs_for(level:, entity_ids:)
        channels_for(level:, entity_ids:).sum { |c| c.subscriber_count.to_i }
      end

      # Distinct channels backing a scope, per level.
      def channels_for(level:, entity_ids:)
        ids = Array(entity_ids)
        case level.to_s
        when "channel"
          ::Channel.where(id: ids).to_a
        when "vid"
          ::Video.where(id: ids).includes(:channel).filter_map(&:channel).uniq(&:id)
        when "game"
          ::Video.joins(:video_game_links).where(video_game_links: { game_id: ids })
                 .includes(:channel).filter_map(&:channel).uniq(&:id)
        else
          []
        end
      end

      # Where the FULL-GREEN anchor sits within the chart's y-range (0.0..1.0),
      # given the y-axis ceiling (= max(series peak, target)). The vertical
      # gradient runs red at 0 → green at this fraction → green to the top.
      def green_anchor_fraction(target:, ceiling:)
        c = ceiling.to_f
        return 1.0 if c <= 0.0

        (target.to_f / c).clamp(0.0, 1.0)
      end
    end
  end
end
