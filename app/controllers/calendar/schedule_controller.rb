# Phase 15 §2 — Calendar Views.
#
# Linear schedule view. Paginated by 50, ordered by starts_at ascending.
# Filter contract (calendar UX restructure):
#
#   - `?types=video,game,custom` — comma-separated list of kind labels;
#     the union of `ENTRY_KIND_FILTERS[<label>]` values is shown.
#   - No `types` param  → all kinds shown.
#   - `?types=` (empty) → no kinds shown.
#   - `?source=<source>` and `?state=all` keep their original semantics.
class Calendar::ScheduleController < ApplicationController
  include CalendarHelper

  PAGE_SIZE = 50

  skip_before_action :verify_authenticity_token, if: -> { request.format.json? }

  def show
    @install_tz = AppSetting.first&.timezone || "UTC"

    scope = CalendarEntry.all
    scope = scope.visible unless params[:state] == "all"

    @selected_kinds = parse_types_param(params[:types])
    if @selected_kinds == :empty
      scope = scope.none
    elsif @selected_kinds.is_a?(Array)
      kinds = @selected_kinds.flat_map { |label| CalendarHelper::ENTRY_KIND_FILTERS[label] }.compact
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
    @selected_source = params[:source]
    @show_cancelled = params[:state] == "all"

    respond_to do |format|
      format.html
      format.json { render :show }
    end
  end

  private

  def parse_types_param(raw)
    return nil if raw.nil?
    values = raw.to_s.split(",").map(&:strip).reject(&:empty?)
    return :empty if values.empty?
    individual = CalendarHelper::ENTRY_KIND_FILTERS.keys - [ "all" ]
    kept = values.select { |v| individual.include?(v) }
    return :empty if kept.empty?
    kept
  end
end
