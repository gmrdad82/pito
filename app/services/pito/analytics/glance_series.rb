# frozen_string_literal: true

module Pito
  module Analytics
    # Day-series for the glance's four charted metrics — views, watched_hours (÷60),
    # net subs (gained − lost), likes — over a period window. Feeds the 2-row
    # braille sparklines in Metric::CompactComponent (ADDITIVE: the scalar totals
    # from Pito::Analytics::Scalars stay separate). Reuses Scalars' channel grouping
    # and Pito::Analytics::DailySeries' daily-primitive fold (the daily report now
    # carries `likes` via AnalyticsClient::METRIC_NAMES). Caching is 0.9.0 scope.
    #
    #   Pito::Analytics::GlanceSeries.for(scope: channel, period: "28d")
    #   # => { views: [..], watched_hours: [..], subs: [..], likes: [..] }
    module GlanceSeries
      METRICS = %i[views watched_hours subs likes avg_view_duration].freeze

      module_function

      # @return [Hash{Symbol=>Array<Numeric>}] metric → daily series; {} when the
      #   scope has no usable channel or a fetch errors (cell then shows scalar only).
      def for(scope:, period:)
        window = Pito::Analytics::Window.for(period, reference_date: Date.current)
        groups = Pito::Analytics::Scalars.channel_groups(scope)
        return {} if groups.blank?

        {
          views:             daily(groups, window, "views"),
          watched_hours:     daily(groups, window, "estimated_minutes_watched").map { |m| (m / 60.0).round(2) },
          subs:              net_subs(groups, window),
          likes:             daily(groups, window, "likes"),
          avg_view_duration: avg_view_duration(groups, window)
        }
      rescue StandardError => e
        Rails.logger.warn("[Analytics::GlanceSeries] #{scope.class}##{scope.try(:id)}: #{e.class}: #{e.message}")
        {}
      end

      def daily(groups, window, metric)
        Pito::Analytics::DailySeries.for(groups:, window:, metric:).series
      end

      # Net subscribers per day = gained − lost (both fold from the same cached
      # daily primitives, so no extra HTTP call).
      def net_subs(groups, window)
        gained = daily(groups, window, "subscribers_gained")
        lost   = daily(groups, window, "subscribers_lost")
        gained.zip(lost).map { |g, l| g.to_i - l.to_i }
      end

      # Average view duration per day (seconds) = watch-minutes ÷ views × 60,
      # derived from the same cached daily primitives (the Analytics daily report
      # has no per-day averageViewDuration, but emw + views are both daily). 0 on
      # a no-view day.
      def avg_view_duration(groups, window)
        emw   = daily(groups, window, "estimated_minutes_watched")
        views = daily(groups, window, "views")
        emw.zip(views).map { |m, v| v.to_i.positive? ? ((m.to_f / v) * 60).round : 0 }
      end
    end
  end
end
