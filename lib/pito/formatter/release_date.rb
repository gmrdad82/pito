# frozen_string_literal: true

module Pito
  module Formatter
    # Pure function. Renders a game's release date as a precision-aware
    # human-readable label.
    #
    # Precision branches (checked in order):
    #   release_year nil, month+day present → "%{month} %{day}" (unknown-year)
    #   release_year nil                    → "TBA"
    #   month + day present                 → the house date (Pito::Formatter::
    #                                          HouseDate.date — "%-d %b" this
    #                                          year, "%-d %b 'YY" otherwise)
    #   month present (no day)              → "%{month} %{year}"
    #   quarter present                     → "Q%{quarter} %{year}"
    #   else                                → "%{year}"
    #
    # The month/quarter/year (no-day) branches keep their full year always —
    # PlatformReleaseGroups groups platform releases BY this very label (it IS
    # the grouping key, not a separate identifier — see platform_release_groups.rb),
    # so year-dropping them would entangle the user-facing label with grouping
    # identity. Only the day-precision branch (a value PlatformReleaseGroups
    # already keeps unique via the day itself) gets the house treatment.
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
          I18n.t("pito.game.release_label.day", date: Pito::Formatter::HouseDate.date(release_date))
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
