# Phase 15 §2 — Calendar Views.
#
# Month grid view. Renders a 6×7 (or 5×7) Monday-first grid with event
# chips per day. Filter contract (calendar UX restructure):
#
#   - `?types=video,game,custom` — comma-separated list of kind labels;
#     the union of `ENTRY_KIND_FILTERS[<label>]` values is shown.
#   - No `types` param   → all kinds shown ("default = all checked").
#   - `?types=` (empty)  → no kinds shown ("all unchecked"); empty result.
#   - `?state=all`       → include cancelled / superseded entries.
#
# `?type=<single>` from the previous contract is no longer accepted; old
# bookmarks fall through to the "all" default. An unknown kind label in
# the csv list is silently dropped (lenient parse).
class Calendar::MonthController < ApplicationController
  include CalendarHelper

  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

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

    @selected_kinds = parse_types_param(params[:types])
    if @selected_kinds == :empty
      scope = scope.none
    elsif @selected_kinds.is_a?(Array)
      kinds = @selected_kinds.flat_map { |label| CalendarHelper::ENTRY_KIND_FILTERS[label] }.compact
      scope = scope.where(entry_type: kinds)
    end

    scope = scope.visible unless params[:state] == "all"

    @entries = scope.order(:starts_at).to_a
    @buckets = @entries.group_by { |e| e.starts_at.in_time_zone(@install_tz).to_date }

    @prev_year, @prev_month = prev_month(year, month)
    @next_year, @next_month = next_month(year, month)
    @today = Time.current.in_time_zone(@install_tz).to_date
    @on_current_month = (@today.year == year && @today.month == month)

    respond_to do |format|
      format.html
      format.json { render :show }
    end
  end

  private

  # Returns:
  #   nil          → no `types` param ("all kinds = all checked default")
  #   :empty       → param present but empty ("all unchecked")
  #   Array<String>→ explicit subset of kind labels (validated)
  def parse_types_param(raw)
    return nil if raw.nil?
    values = raw.to_s.split(",").map(&:strip).reject(&:empty?)
    return :empty if values.empty?
    individual = CalendarHelper::ENTRY_KIND_FILTERS.keys - [ "all" ]
    kept = values.select { |v| individual.include?(v) }
    return :empty if kept.empty?
    kept
  end

  def prev_month(y, m)
    m == 1 ? [ y - 1, 12 ] : [ y, m - 1 ]
  end

  def next_month(y, m)
    m == 12 ? [ y + 1, 1 ] : [ y, m + 1 ]
  end
end
