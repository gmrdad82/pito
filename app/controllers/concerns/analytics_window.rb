# Phase 13.3 — Analytics dashboard. Shared window-picker helper.
#
# The four canonical windows match `analytics_window` Postgres enum
# values from spec 01: `7d`, `28d`, `90d`, `lifetime`. Default is
# `28d` per master-agent decision (matches Studio's default surface).
# Unknown / malformed `?window=` values silently fall back to the
# default — the dashboard renders rather than 422'ing on a stray
# query string. The picker buttons themselves only emit canonical
# values, so the fallback path is reserved for hand-typed URLs and
# bookmarklets.
module AnalyticsWindow
  extend ActiveSupport::Concern

  WINDOWS = %w[7d 28d 90d lifetime].freeze
  DEFAULT_WINDOW = "28d".freeze

  private

  def current_window
    requested = params[:window].to_s
    WINDOWS.include?(requested) ? requested : DEFAULT_WINDOW
  end

  # Translate a window enum value into the inclusive (start, end) date
  # pair the chart partials use to filter daily / slice tables. The
  # `lifetime` window starts at the channel's earliest recorded daily
  # row (or 5 years ago as a hard floor when no rows exist).
  #
  # `today` parameter exists so specs can freeze the boundary; in the
  # request flow this is always `Date.current`.
  def window_dates(window, today: Date.current, lifetime_floor: 5.years.ago.to_date)
    case window
    when "7d"
      [ today - 6, today ]
    when "28d"
      [ today - 27, today ]
    when "90d"
      [ today - 89, today ]
    when "lifetime"
      [ lifetime_floor, today ]
    else
      [ today - 27, today ]
    end
  end
end
