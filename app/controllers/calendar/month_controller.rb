# Phase 15 §2 — Calendar Views.
#
# Month grid view. Renders a 6×7 (or 5×7) Monday-first grid with event
# chips per day. Filters by `?type=` (single value) and `?state=all`
# (include cancelled / superseded).
class Calendar::MonthController < ApplicationController
  include CalendarHelper

  def show
    year  = params[:year].to_i
    month = params[:month].to_i

    if month < 1 || month > 12
      redirect_to calendar_root_path, alert: "invalid month."
      return
    end

    @year = year
    @month = month
    @install_tz = AppSetting.first&.timezone || "UTC"
    tz = ActiveSupport::TimeZone[@install_tz] || ActiveSupport::TimeZone["UTC"]

    grid = month_grid_dates(year, month)
    @grid = grid
    @first_day = grid.first
    @last_day = grid.last + 1.day

    range_start = tz.local(@first_day.year, @first_day.month, @first_day.day)
    range_end = tz.local(@last_day.year, @last_day.month, @last_day.day)

    scope = CalendarEntry.in_range(range_start, range_end)

    if params[:type].present? && params[:type] != "all"
      kinds = CalendarHelper::ENTRY_KIND_FILTERS[params[:type]]
      if kinds.nil?
        redirect_to calendar_root_path, alert: "unknown filter."
        return
      end
      scope = scope.where(entry_type: kinds)
    end

    scope = scope.visible unless params[:state] == "all"

    @entries = scope.order(:starts_at).to_a
    @buckets = @entries.group_by { |e| e.starts_at.in_time_zone(@install_tz).to_date }

    @prev_year, @prev_month = prev_month(year, month)
    @next_year, @next_month = next_month(year, month)
    @today = Time.current.in_time_zone(@install_tz).to_date
    @on_current_month = (@today.year == year && @today.month == month)
    @selected_filter = params[:type] || "all"
  end

  private

  def prev_month(y, m)
    m == 1 ? [ y - 1, 12 ] : [ y, m - 1 ]
  end

  def next_month(y, m)
    m == 12 ? [ y + 1, 1 ] : [ y, m + 1 ]
  end
end
