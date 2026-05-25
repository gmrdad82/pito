module Pito
  # Pito::CalendarController — navigation and state endpoints for the
  # home-screen Calendar panel (`Pito::CalendarPanelComponent`).
  #
  # ## Navigation actions (Turbo Frame swap)
  #
  #   :calendar_prev_month → GET /pito/calendar/prev?month=YYYY-MM
  #   :calendar_next_month → GET /pito/calendar/next?month=YYYY-MM
  #   :calendar_today      → GET /pito/calendar/today
  #   :calendar_pick_year  → GET /pito/calendar/pick_year (stub)
  #
  # ## Mode and filter actions (redirect to / with URL param)
  #
  #   :calendar_set_mode       → GET /pito/calendar/set_mode?mode=month|list
  #   :calendar_filter_category → GET /pito/calendar/filter_category?category=<cat>|""
  #
  # `set_mode` and `filter_category` follow the "no localStorage" hard rule:
  # they redirect to `/` with the resolved param so URL state is canonical and
  # server-rendered truth is preserved.
  #
  # ## Month param contract
  #
  # `?month=YYYY-MM` is required for `prev` and `next`. Invalid or
  # missing values fall back to the current month without raising.
  # `today` and `pick_year` ignore the param.
  #
  # ## Response format
  #
  # Navigation actions: HTML Turbo Frame response rendering
  # `Pito::Calendar::MonthGridComponent` inside the frame wrapper.
  # Mode/filter actions: redirect to `root_path` with the resolved param.
  #
  # ## Cable channel
  #
  # `pito:home:calendar` (inherited from panel; controller does not
  # broadcast independently — nav is a synchronous Turbo Frame swap).
  #
  # ## Related
  #
  # `Pito::Calendar::MonthGridComponent` — the rendered month grid component.
  # `Pito::Calendar::ScheduleListComponent` — the rendered schedule list component.
  # `Pito::Calendar::CategoryColors`     — chip color constants.
  # `CalendarHelper`                     — entry bucketing + filtering.
  # `HomePanelData`                      — resolves `@calendar_mode` + `@calendar_category`.
  class CalendarController < ApplicationController
    include CalendarHelper

    # GET /pito/calendar/prev?month=YYYY-MM
    def prev
      target = parse_month_param(params[:month])
      @target_month = (target - 1.month).beginning_of_month
      render_month_grid
    end

    # GET /pito/calendar/next?month=YYYY-MM
    def next
      target = parse_month_param(params[:month])
      @target_month = (target + 1.month).beginning_of_month
      render_month_grid
    end

    # GET /pito/calendar/today
    def today
      install_tz  = Rails.application.config.x.pito.timezone
      tz          = ActiveSupport::TimeZone[install_tz] || ActiveSupport::TimeZone["UTC"]
      @target_month = Time.current.in_time_zone(tz).to_date.beginning_of_month
      render_month_grid
    end

    # GET /pito/calendar/pick_year
    #
    # Stub — year picker UI is not yet implemented. Returns the current
    # month grid so the frame is not left empty. A follow-up dispatch
    # will replace this with a `Tui::CalendarYearPickerComponent` dialog.
    def pick_year
      install_tz  = Rails.application.config.x.pito.timezone
      tz          = ActiveSupport::TimeZone[install_tz] || ActiveSupport::TimeZone["UTC"]
      @target_month = Time.current.in_time_zone(tz).to_date.beginning_of_month
      render_month_grid
    end

    # GET /pito/calendar/set_mode?mode=month|list
    #
    # Persists the calendar view mode in the URL by redirecting to `/` with
    # `?calendar_mode=<mode>`. Allowed values: "month", "list". Any other
    # value is silently coerced to "month". Preserves any existing
    # `calendar_category` param present in the referrer so the category filter
    # is not lost on mode switch.
    #
    # No localStorage — URL is the canonical state per the hard rule.
    ALLOWED_MODES = %w[month list].freeze

    def set_mode
      raw_mode = params[:mode].to_s
      resolved = ALLOWED_MODES.include?(raw_mode) ? raw_mode : "month"
      redirect_params = { calendar_mode: resolved }
      redirect_params[:calendar_category] = params[:calendar_category] if params[:calendar_category].present?
      redirect_to root_path(redirect_params)
    end

    # GET /pito/calendar/filter_category?category=channel|game|system|manual|""
    #
    # Persists the active category filter in the URL by redirecting to `/`
    # with `?calendar_category=<cat>`. An empty or absent `category` param
    # clears the filter (all categories shown). Preserves `calendar_mode` so
    # the mode is not lost on category switch.
    #
    # Allowed values: "channel", "game", "system", "manual", "" (clear).
    ALLOWED_CATEGORIES = %w[channel game system manual].freeze

    def filter_category
      raw_cat = params[:category].to_s
      redirect_params = {}
      redirect_params[:calendar_mode] = params[:calendar_mode] if params[:calendar_mode].present?
      redirect_params[:calendar_category] = raw_cat if ALLOWED_CATEGORIES.include?(raw_cat)
      redirect_to root_path(redirect_params)
    end

    private

    # Parse "YYYY-MM" into the first-of-month Date. Falls back to today's
    # month on any parse error (missing param, wrong format, invalid date).
    def parse_month_param(raw)
      return Date.current.beginning_of_month if raw.blank?
      Date.parse("#{raw}-01")
    rescue ArgumentError, TypeError
      Date.current.beginning_of_month
    end

    def render_month_grid
      install_tz = Rails.application.config.x.pito.timezone
      tz         = ActiveSupport::TimeZone[install_tz] || ActiveSupport::TimeZone["UTC"]
      today      = Time.current.in_time_zone(tz).to_date

      grid_month = @target_month

      # Build the 6×7 grid to determine the date window for the query.
      first      = grid_month
      grid_start = first - first.wday.days  # Sunday-first
      grid_end   = grid_start + 41.days

      range_start = tz.local(grid_start.year, grid_start.month, grid_start.day)
      range_end   = tz.local(grid_end.year,   grid_end.month,   grid_end.day + 1)

      raw_filter = params[:calendar_filter]
      scope = CalendarEntry.in_range(range_start, range_end).visible.order(:created_at)
      scope = home_calendar_filter_scope(scope, raw_filter)
      entries = scope.to_a

      @component = Pito::Calendar::MonthGridComponent.new(
        entries:         entries,
        month:           grid_month,
        today:           today,
        category_filter: nil
      )

      render @component
    end

    # Delegate to HomePanelData's calendar filter helper.
    def home_calendar_filter_scope(scope, raw_filter)
      return scope if raw_filter.nil?
      active = CalendarHelper::PANEL_CALENDAR_CATEGORIES.keys.select { |k| raw_filter[k].to_s == "on" }
      return scope.none if active.empty?
      types = active.flat_map { |cat| CalendarHelper::PANEL_CALENDAR_CATEGORIES[cat] }.compact
      scope.where(entry_type: types)
    end
  end
end
