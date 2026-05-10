# Phase 15 §2 — Calendar Views.
#
# Linear schedule view. Paginated by 50, ordered by starts_at ascending.
# Filters by `?type=` and `?source=`.
class Calendar::ScheduleController < ApplicationController
  include CalendarHelper

  PAGE_SIZE = 50

  def show
    @install_tz = AppSetting.first&.timezone || "UTC"

    scope = CalendarEntry.all
    scope = scope.visible unless params[:state] == "all"

    if params[:type].present? && params[:type] != "all"
      kinds = CalendarHelper::ENTRY_KIND_FILTERS[params[:type]]
      if kinds.nil?
        redirect_to calendar_schedule_path, alert: "unknown filter."
        return
      end
      scope = scope.where(entry_type: kinds)
    end

    if params[:source].present?
      unless CalendarEntry.sources.key?(params[:source])
        redirect_to calendar_schedule_path, alert: "unknown source."
        return
      end
      scope = scope.where(source: params[:source])
    end

    @total = scope.count
    @page  = (params[:page] || 1).to_i
    @page  = 1 if @page < 1
    @total_pages = [ (@total / PAGE_SIZE.to_f).ceil, 1 ].max

    @entries = scope.order(:starts_at).limit(PAGE_SIZE).offset((@page - 1) * PAGE_SIZE).to_a
    @today = Time.current
    @selected_filter = params[:type] || "all"
    @selected_source = params[:source]
    @show_cancelled = params[:state] == "all"
  end
end
