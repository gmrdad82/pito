# frozen_string_literal: true

module Pito
  module Analytics
    # Computes a VIEWS-WEIGHTED average of a per-day YouTube average metric, with
    # ADAPTIVE time bucketing over a shift+space window.
    #
    # `value_key` picks which YouTube per-day average to weight:
    #   :average_view_duration   → avg view duration (seconds)   [default]
    #   :average_view_percentage → avg percentage viewed (%)
    #
    # These are PULLED from YouTube's own per-day columns (owner: never re-derive
    # what YouTube supplies). YouTube reports one average per video per day; a scope
    # spanning multiple videos/channels has no single YouTube average, so we combine
    # them by VIEWS WEIGHTING — the only bit YouTube can't do for us:
    #   Σ(value × views) / Σ(views)   per bucket  [Float]
    # A day with 0 views contributes 0 to both, so empty days drop out naturally.
    #
    # Bucketing (mirrors YouTube Studio):
    #   period ≤ 30 days → daily · 31–90 → weekly (ISO) · > 90 → monthly.
    #
    # Reuses `DailySeries.primitives_daily` (memoised via AnalyticsPrimitive) — no
    # extra YouTube call.
    #
    #   result = Pito::Analytics::AdaptiveSeries.for(groups:, window:)                               # duration
    #   result = Pito::Analytics::AdaptiveSeries.for(groups:, window:, value_key: :average_view_percentage)
    #   result.series  # => [42.1, 38.9, …]  (value per bucket)
    #   result.total   # => 40.3             (overall views-weighted average)
    module AdaptiveSeries
      # `dates` carries the representative (first) date of each bucket so callers
      # can render date-labelled x-ticks. Parallel to `series` (same length).
      Result = Data.define(:series, :total, :dates)

      DAILY_MAX_DAYS  = 30  # ≤ this → daily buckets
      WEEKLY_MAX_DAYS = 90  # ≤ this → weekly; > this → monthly

      module_function

      # @param groups    [Array<[Channel, Array<String>|:channel]>]
      # @param window    [Pito::Analytics::Window]
      # @param value_key [Symbol] :average_view_duration | :average_view_percentage
      # @return [Result]
      def for(groups:, window:, value_key: :average_view_duration)
        period_days = (window.end_date - window.start_date).to_i + 1

        raw = Pito::Analytics::DailySeries.primitives_daily(groups:, window:)

        by_day = Hash.new { |h, k| h[k] = { views: 0, weighted: 0.0 } }
        raw.each_value do |rows|
          Array(rows).each do |row|
            next unless row.is_a?(Hash)

            day = Pito::Analytics::DailySeries.parse_day(row["day"] || row[:day])
            next unless day

            views = (row["views"] || row[:views]).to_i
            value = (row[value_key.to_s] || row[value_key]).to_f

            by_day[day][:views]    += views
            by_day[day][:weighted] += value * views   # views-weighted numerator
          end
        end

        dates   = (window.start_date..window.end_date).to_a
        buckets = bucket_dates(dates, period_days)

        series = buckets.map do |bucket_days|
          v = bucket_days.sum { |d| by_day[d][:views] }
          w = bucket_days.sum { |d| by_day[d][:weighted] }
          v > 0 ? (w / v).round(1) : 0.0
        end

        # First date of each bucket as the representative x-tick date.
        bucket_dates = buckets.map(&:first)

        all_views    = by_day.values.sum { |e| e[:views] }
        all_weighted = by_day.values.sum { |e| e[:weighted] }
        total = all_views > 0 ? (all_weighted / all_views).round(1) : 0.0

        Result.new(series:, total:, dates: bucket_dates)
      end

      # Group a date range into buckets based on the period length.
      # @param dates      [Array<Date>]
      # @param period_days [Integer]
      # @return [Array<Array<Date>>] ordered array of day-groups
      def bucket_dates(dates, period_days)
        case period_days
        when 1..DAILY_MAX_DAYS
          dates.map { |d| [ d ] }
        when (DAILY_MAX_DAYS + 1)..WEEKLY_MAX_DAYS
          group_by_key(dates) { |d| [ d.cwyear, d.cweek ] }
        else
          group_by_key(dates) { |d| [ d.year, d.month ] }
        end
      end

      # Stable key-based grouping that preserves the original chronological order
      # of groups (same order as the dates array).
      def group_by_key(dates, &key_fn)
        groups = {}
        order  = []
        dates.each do |d|
          k = key_fn.call(d)
          unless groups.key?(k)
            groups[k] = []
            order << k
          end
          groups[k] << d
        end
        order.map { |k| groups[k] }
      end
    end
  end
end
