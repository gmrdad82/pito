# frozen_string_literal: true

module Pito
  module Analytics
    # Per-metric "health" thresholds that drive each chart's red→green gradient.
    # The threshold is subscriber-aware so a small channel isn't unfairly red.
    #
    # VIEWS:
    #   target_daily = VIEWS_M × subscribers / 7   (per-WEEK pace — the green line
    #   sits at the same daily height regardless of the chosen period; only the
    #   chart's x-span changes). "Full green" ≈ pulling roughly your subscriber
    #   count in views every week. VIEWS_M is the single tunable difficulty knob.
    #
    # SUBS (net):
    #   target_daily = subs × SUBS_WEEKLY_GROWTH / 7   (1%/week net-subscriber pace).
    #   Tune SUBS_WEEKLY_GROWTH to move the green bar.
    #
    # WATCHED HOURS:
    #   target_daily = views_target_daily × DEFAULT_AVG_VIEW_HOURS   (~3 minutes/view
    #   default; refine to the scope's real avg_view_duration later).
    #
    # Subscriber basis per level: channel = the channel(s); vid = its channel;
    # game = Σ distinct channels owning the linked vids. subs are READ from
    # the DB (subscriber_count column) — never mutated here.
    module Thresholds
      VIEWS_M              = 1.0   # views difficulty multiplier — ONE place to tune "how green is green"
      SUBS_WEEKLY_GROWTH   = 0.01  # owner-tunable: expected net-subscriber growth rate per week (1%)
      DEFAULT_AVG_VIEW_HOURS = 0.05 # owner-tunable: fallback avg view duration in hours (~3 min)
      WEEK                 = 7.0

      # "Full-green" avg view duration target (seconds). Green when the scope's
      # average viewer watches at least 2 minutes per view. Tune here only.
      AVG_VIEW_DURATION_TARGET_SECONDS = 120

      # "Full-green" average audience-retention target (percentage, 0–100).
      # Green when the average viewer watches at least 50% of a video.
      RETENTION_TARGET_PCT = 50

      module_function

      # Unified per-metric target_daily dispatcher — the single entry point for
      # all chart thresholds. Returns the daily "full-green" target for `metric`
      # given the scope's `subs` count. Pass `views_target_daily:` to avoid
      # recomputing it when it is already known (used by watched_hours formula).
      #
      # @param metric [Symbol] :views | :watched_hours | :subs
      # @param subs   [Integer] subscriber count for the scope
      # @param views_target_daily [Float, nil] precomputed views target (optional)
      # @return [Float]
      def target_daily(metric:, subs:, views_target_daily: nil)
        case metric.to_sym
        when :views              then views_target_daily(subs:)
        when :subs               then subs_target_daily(subs:)
        when :watched_hours      then watched_hours_target_daily(views_target_daily: views_target_daily || views_target_daily(subs:))
        when :avg_view_duration  then AVG_VIEW_DURATION_TARGET_SECONDS.to_f
        when :avg_viewed_pct     then RETENTION_TARGET_PCT.to_f
        else 0.0
        end
      end

      # Daily full-green Views target for a scope of `subs` subscribers.
      def views_target_daily(subs:)
        s = subs.to_i
        return 0.0 if s <= 0

        VIEWS_M * s / WEEK
      end

      # Daily full-green net-subscribers target (1%/week growth pace).
      def subs_target_daily(subs:)
        s = subs.to_i
        return 0.0 if s <= 0

        SUBS_WEEKLY_GROWTH * s / WEEK
      end

      # Daily full-green Watched Hours target (views_target × default avg view duration).
      def watched_hours_target_daily(views_target_daily:)
        views_target_daily.to_f * DEFAULT_AVG_VIEW_HOURS
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
