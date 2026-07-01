# frozen_string_literal: true

module Pito
  module Analytics
    # Folds a scope's daily VIEWS primitives into an AVERAGE-views-per-weekday
    # vector (Monday→Sunday) over a window — the data behind the day-of-week
    # heatmap. YouTube has no weekday dimension for historical data, so we compute
    # it from the per-day rows PITO already caches (owner: compute what YouTube
    # can't give us for the scope; never re-derive what it does).
    #
    # Method: sum views per CALENDAR day across every subject in the scope, group
    # those calendar-day totals by ISO weekday, and average — so a weekday's value
    # is "the typical day's views for that weekday", not skewed by how many
    # subjects/rows a day happened to carry. Days YouTube returned no row for
    # simply don't count toward that weekday's average.
    #
    #   Pito::Analytics::WeekdaySeries.for(groups:, window:)
    #   # => Result(values: [Mon, Tue, Wed, Thu, Fri, Sat, Sun])  # 7 Floats
    module WeekdaySeries
      # `values` is ALWAYS length 7, index 0 = Monday … 6 = Sunday (ISO cwday−1).
      Result = Data.define(:values)

      DAYS = 7

      module_function

      # @param groups [Array<[Channel, Array<String> | :channel]>]
      # @param window [Pito::Analytics::Window]
      # @return [Result]
      def for(groups:, window:)
        by_day = Hash.new(0)
        Pito::Analytics::DailySeries.primitives_daily(groups:, window:).each_value do |rows|
          Array(rows).each do |row|
            next unless row.is_a?(Hash)

            day = Pito::Analytics::DailySeries.parse_day(row["day"] || row[:day])
            by_day[day] += (row["views"] || row[:views]).to_i if day
          end
        end

        buckets = Array.new(DAYS) { { sum: 0, count: 0 } }
        by_day.each do |day, views|
          b = buckets[day.cwday - 1] # cwday 1(Mon)..7(Sun) → 0..6
          b[:sum]   += views
          b[:count] += 1
        end

        values = buckets.map { |b| b[:count].positive? ? (b[:sum].to_f / b[:count]).round(1) : 0.0 }
        Result.new(values:)
      end
    end
  end
end
