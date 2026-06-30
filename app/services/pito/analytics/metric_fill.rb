# frozen_string_literal: true

module Pito
  module Analytics
    # Fetches ONE glance metric via its OWN dedicated YouTube Analytics request —
    # both the scalar (aggregate, no dimension) AND its day-series — independent of
    # every other metric. So each metric is fault-isolated: one metric's request
    # failing (or its channel erroring) never sinks the rest of the glance. Quota is
    # deliberately NOT a concern here (owner-directed): one HTTP call per metric per
    # channel group, fanned out by AnalyticsMetricJob.
    #
    # `for(scope:, period:, key:)` returns a Cell (a single-metric Scalars::Result +
    # the metric's series, keyed the way ScalarsTableComponent expects) or
    # UNAVAILABLE when the scope has no usable channel or the request errors.
    module MetricFill
      UNAVAILABLE = :unavailable

      Cell = Data.define(:result, :series)

      module_function

      def for(scope:, period:, key:)
        key    = key.to_s
        window = Pito::Analytics::Window.for(period, reference_date: Date.current)
        groups = Pito::Analytics::Scalars.channel_groups(scope)
        return UNAVAILABLE if groups.blank?

        rows = fetch(groups, window, scalar_metric_names(key))
        # No rows = no data for this metric/range (empty response, or a quota error
        # that normalized to nothing). Treat as unavailable → the cell shows the
        # NoData canvas + "n/a", same as a raised request below.
        return UNAVAILABLE if rows.blank?

        result = Pito::Analytics::Scalars::Result.new(
          metrics:    fold_scalar(key, rows),
          label:      window.label,
          comparable: window.comparable?
        )
        Cell.new(result:, series: series_metrics(groups, window, key))
      rescue StandardError => e
        Rails.logger.warn("[Analytics::MetricFill] #{scope.class}##{scope.try(:id)} #{key}: #{e.class}: #{e.message}")
        UNAVAILABLE
      end

      # ── scalar (aggregate, no dimension) — one dedicated request per group ───────

      def scalar_metric_names(key)
        case key
        when "views"             then "views"
        when "watched_hours"     then "estimatedMinutesWatched"
        when "avg_view_duration" then "averageViewDuration,views"
        when "subs_net"          then "subscribersGained,subscribersLost"
        when "likes"             then "likes,dislikes"
        end
      end

      def fold_scalar(key, rows)
        case key
        when "views"
          { views: cur(rows.sum { |r| r[:views].to_i }) }
        when "watched_hours"
          mins = rows.sum { |r| r[:estimated_minutes_watched].to_i }
          { watched_hours: cur((mins / 60.0).round(1)) }
        when "avg_view_duration"
          views = rows.sum { |r| r[:views].to_i }
          wtd   = rows.sum { |r| r[:average_view_duration].to_f * r[:views].to_i }
          { avg_view_duration: cur(views.positive? ? (wtd / views).round : 0) }
        when "subs_net"
          { subs_gained: cur(rows.sum { |r| r[:subscribers_gained].to_i }),
            subs_lost:   cur(rows.sum { |r| r[:subscribers_lost].to_i }) }
        when "likes"
          { likes:    cur(rows.sum { |r| r[:likes].to_i }),
            dislikes: cur(rows.sum { |r| r[:dislikes].to_i }) }
        end
      end

      # ── series (daily) — one dedicated request per group, summed by day ─────────

      def series_metrics(groups, window, key)
        rows = daily(groups, window, series_metric_names(key))
        fold_series(key, rows)
      end

      def series_metric_names(key)
        case key
        when "views"             then "views"
        when "watched_hours"     then "estimatedMinutesWatched"
        when "avg_view_duration" then "views,estimatedMinutesWatched"
        when "subs_net"          then "subscribersGained,subscribersLost"
        when "likes"             then "likes"
        end
      end

      def fold_series(key, rows)
        by_day = Hash.new { |h, k| h[k] = Hash.new(0) }
        rows.each do |r|
          day = r[:day]
          next unless day

          %i[views estimated_minutes_watched subscribers_gained subscribers_lost likes].each do |col|
            by_day[day][col] += r[col].to_i
          end
        end
        days = by_day.keys.sort
        case key
        when "views"             then { views:         days.map { |d| by_day[d][:views] } }
        when "watched_hours"     then { watched_hours: days.map { |d| (by_day[d][:estimated_minutes_watched] / 60.0).round(2) } }
        when "likes"             then { likes:         days.map { |d| by_day[d][:likes] } }
        when "subs_net"          then { subs:          days.map { |d| by_day[d][:subscribers_gained] - by_day[d][:subscribers_lost] } }
        when "avg_view_duration"
          { avg_view_duration: days.map { |d| v = by_day[d][:views]; v.positive? ? ((by_day[d][:estimated_minutes_watched].to_f / v) * 60).round : 0 } }
        end
      end

      # ── dedicated HTTP, one request per channel group ───────────────────────────

      def fetch(groups, window, metrics)
        groups.filter_map do |channel, video_ids|
          ::Channel::Youtube::AnalyticsClient
            .new(channel.youtube_connection)
            .query(channel_id: channel.youtube_channel_id, start_date: window.start_date,
                   end_date: window.end_date, metrics:, filters: video_filter(video_ids))
            &.first
            &.presence
        end
      end

      def daily(groups, window, metrics)
        groups.flat_map do |channel, video_ids|
          ::Channel::Youtube::AnalyticsClient
            .new(channel.youtube_connection)
            .query(channel_id: channel.youtube_channel_id, start_date: window.start_date,
                   end_date: window.end_date, metrics:, dimensions: "day", filters: video_filter(video_ids))
        end
      end

      def video_filter(video_ids)
        ids = Array(video_ids)
        ids.present? ? "video==#{ids.join(',')}" : nil
      end

      def cur(value) = { current: value, previous: nil }
    end
  end
end
