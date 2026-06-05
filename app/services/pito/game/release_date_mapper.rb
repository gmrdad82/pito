# frozen_string_literal: true

# Source-agnostic mapper that translates a normalized component hash into the
# 5-column attribute hash stored on `Game`.
#
# Documented in `docs/architecture.md` § "Game release-date representation".
#
# Input shape (every key optional):
#   { year: Integer, quarter: 1..4, month: 1..12, day: 1..31 }
#
# Output shape (always all 5 keys; nils explicit):
#   {
#     release_year:   Integer | nil,
#     release_quarter: Integer | nil,
#     release_month:  Integer | nil,
#     release_day:    Integer | nil,
#     release_date:   Date | nil,  # derived lower-bound; never the source of truth
#   }
module Pito
  module Game
    class ReleaseDateMapper
      QUARTER_START_MONTH = {
        1 => 1,
        2 => 4,
        3 => 7,
        4 => 10
      }.freeze

      def self.call(components = {})
        new(components).call
      end

      def initialize(components)
        @components = normalize(components)
      end

      def call
        validate!

        year  = @components[:year]
        quarter = @components[:quarter]
        month = @components[:month]
        day   = @components[:day]

        release_date = derive_date(year, quarter, month, day)

        {
          release_year:    year,
          release_quarter: quarter,
          release_month:   month,
          release_day:     day,
          release_date:    release_date
        }
      end

      private

      def normalize(components)
        return {} if components.nil?

        components.each_with_object({}) do |(key, value), hash|
          sym_key = key.to_sym
          hash[sym_key] = value.is_a?(String) ? value.to_i : value
        end
      end

      def validate!
        year    = @components[:year]
        quarter = @components[:quarter]
        month   = @components[:month]
        day     = @components[:day]

        if quarter.present? && month.present?
          raise Pito::Error::ReleaseDateInconsistent.new(
            reason: "quarter and month are mutually exclusive",
            components: @components
          )
        end

        if day.present? && month.nil?
          raise Pito::Error::ReleaseDateInconsistent.new(
            reason: "day requires month",
            components: @components
          )
        end

        if quarter.present? && !quarter.between?(1, 4)
          raise Pito::Error::ReleaseDateInconsistent.new(
            reason: "quarter out of range",
            components: @components
          )
        end

        if month.present? && !month.between?(1, 12)
          raise Pito::Error::ReleaseDateInconsistent.new(
            reason: "month out of range",
            components: @components
          )
        end

        if year.present? && month.present? && day.present?
          begin
            Date.new(year, month, day)
          rescue Date::Error
            raise Pito::Error::ReleaseDateInconsistent.new(
              reason: "invalid date",
              components: @components
            )
          end
        end
      end

      def derive_date(year, quarter, month, day)
        return nil if year.nil? && month.nil?

        if year.present? && month.present? && day.present?
          Date.new(year, month, day)
        elsif year.present? && month.present?
          Date.new(year, month, 1)
        elsif year.present? && quarter.present?
          Date.new(year, QUARTER_START_MONTH[quarter], 1)
        elsif year.present?
          Date.new(year, 1, 1)
        else
          nil
        end
      end
    end
  end
end
