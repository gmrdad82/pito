# frozen_string_literal: true

module Pito
  module Formatter
    # Pure function. Renders a game's release date as a precision-aware
    # human-readable label.
    #
    # Precision branches (checked in order):
    #   release_year nil, month+day present → "%{month} %{day}" (unknown-year)
    #   release_year nil                    → "TBA"
    #   month + day present                 → I18n.l(release_date, format: :long)
    #   month present (no day)              → "%{month} %{year}"
    #   quarter present                     → "Q%{quarter} %{year}"
    #   else                                → "%{year}"
    #
    # I18n keys used: pito.game.release_label.{day,month_year,quarter_year,year,
    #                                           month_day_unknown_year,tba}
    module ReleaseDate
      module_function

      def call(game)
        release_year    = game.release_year
        release_month   = game.release_month
        release_day     = game.release_day
        release_quarter = game.release_quarter
        release_date    = game.release_date

        if release_year.nil?
          if release_month.present? && release_day.present?
            return I18n.t("pito.game.release_label.month_day_unknown_year",
                          month: Date::MONTHNAMES[release_month],
                          day:   release_day)
          end

          return I18n.t("pito.game.release_label.tba")
        end

        if release_month.present? && release_day.present?
          I18n.t("pito.game.release_label.day", date: I18n.l(release_date, format: :long))
        elsif release_month.present?
          I18n.t("pito.game.release_label.month_year",
                 month: Date::MONTHNAMES[release_month],
                 year:  release_year)
        elsif release_quarter.present?
          I18n.t("pito.game.release_label.quarter_year",
                 quarter: release_quarter,
                 year:    release_year)
        else
          I18n.t("pito.game.release_label.year", year: release_year)
        end
      end
    end
  end
end
