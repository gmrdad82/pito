# frozen_string_literal: true

module Pito
  module Analytics
    # Fills ONE glance metric — scalar + day-series — by FOLDING from the shared
    # primitives cache instead of firing dedicated requests.
    #
    # One warm (scalars, daily) primitive pair per subject serves ALL five
    # glance metrics: the first metric to run fetches any cold subjects (one
    # atomic request per subject per report, stored with the Window-derived
    # TTL); the other four fold from the same rows for free. The pre-0.9.0
    # shape fired 2 dedicated HTTP requests per metric per channel group —
    # 10 per glance, every time, cached nowhere.
    #
    # Fault isolation is unchanged: each metric's fold runs in its own
    # `for` call with its own rescue, so one metric erroring (or its cold
    # fetch failing) never sinks the rest of the glance — its cell shows the
    # NoData canvas while the others fill.
    #
    # Subjects follow the Primitives group model: per-video rows for vid/game
    # scopes; ONE channel-wide row (`:channel`) for channel scope. Metrics come
    # back string-keyed (jsonb round-trip) — folds read string keys.
    #
    # `for(scope:, period:, key:)` returns a Cell (single-metric
    # Scalars::Result + the metric's series, keyed the way
    # ScalarsTableComponent expects) or UNAVAILABLE.
    module MetricFill
      UNAVAILABLE = :unavailable

      Cell = Data.define(:result, :series)

      module_function

      def for(scope:, period:, key:)
        key    = key.to_s
        window = Pito::Analytics::Window.for(period, reference_date: Date.current)
        groups = primitive_groups(scope)
        return UNAVAILABLE if groups.blank?

        rows = Pito::Analytics::Primitives.fetch(groups:, window:, report: "scalars").values
        return UNAVAILABLE if rows.all?(&:blank?)

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

      # Scope → primitives groups: reuses Scalars.channel_groups (the canonical
      # scope walk) and maps its channel-level `[]` marker to the `:channel`
      # subject Primitives expects (one channel-wide row, not a per-vid sum).
      def primitive_groups(scope)
        Pito::Analytics::Scalars.channel_groups(scope).map do |channel, video_ids|
          [ channel, video_ids.blank? ? :channel : video_ids ]
        end
      end

      # ── scalar folds (string-keyed subject rows from the scalars primitive) ──────

      def fold_scalar(key, rows)
        case key
        when "views"
          { views: cur(sum(rows, "views")) }
        when "watched_hours"
          { watched_hours: cur((sum(rows, "estimated_minutes_watched") / 60.0).round(1)) }
        when "avg_view_duration"
          views = sum(rows, "views")
          wtd   = rows.sum { |r| r["average_view_duration"].to_f * r["views"].to_i }
          { avg_view_duration: cur(views.positive? ? (wtd / views).round : 0) }
        when "subs_net"
          { subs_gained: cur(sum(rows, "subscribers_gained")),
            subs_lost:   cur(sum(rows, "subscribers_lost")) }
        when "likes"
          { likes:    cur(sum(rows, "likes")),
            dislikes: cur(sum(rows, "dislikes")) }
        end
      end

      def sum(rows, metric_key)
        rows.sum { |r| r[metric_key].to_i }
      end

      # ── series folds (per-day rows from the daily primitive) ────────────────────

      # The daily report gained `likes` in 0.9.0 — older warm rows lack the key
      # and must refetch once for the likes sparkline (require_keys).
      def series_metrics(groups, window, key)
        required = key == "likes" ? [ "likes" ] : []
        daily    = Pito::Analytics::Primitives.fetch(groups:, window:, report: "daily", require_keys: required)
        fold_series(key, daily.values.flatten.select { |r| r.is_a?(Hash) })
      end

      def fold_series(key, rows)
        by_day = Hash.new { |h, k| h[k] = Hash.new(0) }
        rows.each do |r|
          day = r["day"]
          next if day.blank?

          %w[views estimated_minutes_watched subscribers_gained subscribers_lost likes].each do |col|
            by_day[day][col] += r[col].to_i
          end
          # YouTube's own per-day average, views-weighted across subjects (never re-derived).
          by_day[day]["weighted_duration"] += r["average_view_duration"].to_f * r["views"].to_i
        end
        days = by_day.keys.sort
        case key
        when "views"             then { views:         days.map { |d| by_day[d]["views"] } }
        when "watched_hours"     then { watched_hours: days.map { |d| (by_day[d]["estimated_minutes_watched"] / 60.0).round(2) } }
        when "likes"             then { likes:         days.map { |d| by_day[d]["likes"] } }
        when "subs_net"          then { subs:          days.map { |d| by_day[d]["subscribers_gained"] - by_day[d]["subscribers_lost"] } }
        when "avg_view_duration"
          { avg_view_duration: days.map { |d| v = by_day[d]["views"]; v.positive? ? (by_day[d]["weighted_duration"] / v).round : 0 } }
        end
      end

      def cur(value) = { current: value, previous: nil }
    end
  end
end
