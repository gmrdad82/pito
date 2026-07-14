# frozen_string_literal: true

module Pito
  module Analytics
    # Pre-fills one channel's analytics caches so the owner's interactive
    # turns land warm: runs the EXACT fill fan-outs `show` (glance) and
    # `analyze`/`breakdowns` would run — same services, same primitives, same
    # Window-policy TTLs — just ahead of time from the recurring schedule
    # (see AnalyticsWarmupJob). Nothing here invents a fetch path: warming IS
    # the production fill, so a warmed cell is byte-identical to an on-demand
    # one and repeat turns fold from the same rows.
    #
    # Coverage (channel scope only — vid/game turns still warm organically):
    #   - glance: every GLANCE_METRICS key, per period token below.
    #   - analyze/breakdowns: MetricOrder's :system role per period token,
    #     plus the :enhanced role once (its metrics are lifetime-fixed —
    #     that pass is what warms the breakdown bars and retention).
    #
    # Period tokens: "7d" is the conversation default (conversations.stats_period),
    # "28d" the common shift+space window (the bench's canonical token —
    # lib/pito/bench/steps/cold_paths.rb). Live windows expire after 4h
    # (Window policy), so warmth depends on the AnalyticsWarmupJob cadence.
    #
    # Error posture: the fill entry points already rescue per metric
    # (UNAVAILABLE / no_data + a warn log), so one bad metric never aborts
    # the sweep; a systemic failure (revoked OAuth) surfaces as logs, and the
    # per-channel rescue lives in the job.
    module Warmup
      PERIODS = %w[7d 28d].freeze

      module_function

      # @param channel [Channel] a connected (non-reauth) channel
      # @return [void]
      def call(channel:)
        glance_keys = Pito::Analytics::ScalarsTableComponent::GLANCE_METRICS.map { |m| m[:key].to_s }

        PERIODS.each do |period|
          glance_keys.each do |key|
            Pito::Analytics::MetricFill.for(scope: channel, period:, key:)
          end

          Pito::Analytics::MetricOrder.for(role: :system, level: :channel).each do |metric|
            Pito::Analytics::AnalyzeMetricFill.for(metric:, level: :channel, entity_ids: [ channel.id ], period:)
          end
        end

        # Enhanced-role metrics read at LIFETIME regardless of period — one
        # pass warms them (breakdown bars, likes hearts, retention, heatmap).
        Pito::Analytics::MetricOrder.for(role: :enhanced, level: :channel).each do |metric|
          Pito::Analytics::AnalyzeMetricFill.for(metric:, level: :channel, entity_ids: [ channel.id ], period: "lifetime")
        end
      end
    end
  end
end
