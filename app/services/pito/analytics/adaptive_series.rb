# frozen_string_literal: true

module Pito
  module Analytics
    # Computes a views-weighted average-view-duration series with ADAPTIVE
    # time bucketing over a shift+space window.
    #
    # Bucketing rules (mirrors YouTube Studio's time-grouping behaviour):
    #   period ≤ 30 days  → daily (one value per day)
    #   31–90 days        → weekly (ISO week groups)
    #   > 90 days         → monthly (calendar month groups)
    #
    # Per-bucket value:
    #   Σ(estimated_minutes_watched × 60) / Σ(views)  [seconds, Float]
    #
    # The formula is a views-weighted average — a day with 0 views contributes
    # 0 to both numerator and denominator, so empty days are naturally excluded.
    # The total is the overall weighted average across the whole period.
    #
    # Reuses `DailySeries.primitives_daily` (already memoised via
    # AnalyticsPrimitive) so no extra YouTube API call is needed.
    #
    #   result = Pito::Analytics::AdaptiveSeries.for(groups:, window:)
    #   result.series  # => [120.5, 95.2, …]  (seconds per bucket)
    #   result.total   # => 108.3              (overall avg seconds)
    module AdaptiveSeries
      # `dates` carries the representative (first) date of each bucket so callers
      # can render date-labelled x-ticks. Parallel to `series` (same length).
      Result = Data.define(:series, :total, :dates)

      DAILY_MAX_DAYS  = 30  # ≤ this → daily buckets
      WEEKLY_MAX_DAYS = 90  # ≤ this → weekly; > this → monthly

      module_function

      # @param groups [Array<[Channel, Array<String>|:channel]>]
      # @param window [Pito::Analytics::Window]
      # @return [Result]
      def for(groups:, window:)
        period_days = (window.end_date - window.start_date).to_i + 1

        raw = Pito::Analytics::DailySeries.primitives_daily(groups:, window:)

        by_day = Hash.new { |h, k| h[k] = { views: 0, minutes: 0 } }
        raw.each_value do |rows|
          Array(rows).each do |row|
            next unless row.is_a?(Hash)

            day = Pito::Analytics::DailySeries.parse_day(row["day"] || row[:day])
            next unless day

            by_day[day][:views]   += (row["views"]   || row[:views]).to_i
            by_day[day][:minutes] += (row["estimated_minutes_watched"] || row[:estimated_minutes_watched]).to_i
          end
        end

        dates   = (window.start_date..window.end_date).to_a
        buckets = bucket_dates(dates, period_days)

        series = buckets.map do |bucket_days|
          v = bucket_days.sum { |d| by_day[d][:views] }
          m = bucket_days.sum { |d| by_day[d][:minutes] }
          v > 0 ? (m * 60.0 / v).round(1) : 0.0
        end

        # First date of each bucket as the representative x-tick date.
        bucket_dates = buckets.map(&:first)

        all_views   = by_day.values.sum { |e| e[:views] }
        all_minutes = by_day.values.sum { |e| e[:minutes] }
        total = all_views > 0 ? (all_minutes * 60.0 / all_views).round(1) : 0.0

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
