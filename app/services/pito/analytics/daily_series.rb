# frozen_string_literal: true

module Pito
  module Analytics
    # Folds the per-subject `daily` PRIMITIVES for a scope into ONE contiguous
    # per-day series for a single metric (default Views), plus the period total.
    #
    # The `daily` report returns, per subject, an array of per-day rows
    # ({ "day" => "2026-06-01", "views" => 12, "estimated_minutes_watched" => 34 }).
    # A scope can be one channel-wide subject (channel level), one video (vid), or
    # many videos across channels (game) — we simply SUM the chosen metric per
    # calendar day across every subject, then emit one value for EVERY day in the
    # window (0-filled where YouTube returned no row).
    #
    #   Pito::Analytics::DailySeries.for(groups:, window:)            # views
    #   Pito::Analytics::DailySeries.for(groups:, window:, metric: "estimated_minutes_watched")
    #   # => Result(dates: [Date, …], series: [Integer, …], total: Integer)
    #
    # Generic by metric so later charts (watch-hours, …) reuse the same fold. The
    # series sum IS the scalar total for that metric over the window.
    module DailySeries
      Result = Data.define(:dates, :series, :total)

      module_function

      # @param groups [Array<[Channel, Array<String> | :channel]>] (as Primitives.fetch)
      # @param window [Pito::Analytics::Window]
      # @param metric [String] daily row key to fold (default "views")
      # @return [Result]
      def for(groups:, window:, metric: "views")
        dates  = (window.start_date..window.end_date).to_a
        by_day = Hash.new(0)

        primitives_daily(groups:, window:).each_value do |rows|
          Array(rows).each do |row|
            next unless row.is_a?(Hash)

            day = parse_day(row["day"] || row[:day])
            by_day[day] += (row[metric] || row[metric.to_sym]).to_i if day
          end
        end

        series = dates.map { |d| by_day[d] }
        Result.new(dates:, series:, total: series.sum)
      end

      def primitives_daily(groups:, window:)
        Pito::Analytics::Primitives.fetch(groups:, window:, report: "daily")
      end

      def parse_day(value)
        return value if value.is_a?(Date)

        Date.parse(value.to_s)
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
