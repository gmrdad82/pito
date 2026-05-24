module Pito
  # Pito::CalendarPanelComponent — home-screen calendar panel.
  #
  # Renders a Monday-first month grid with day cells, colored per-entry
  # bullets, and 4 category filter chips above the grid.
  #
  # ## View toggle
  #
  # Two-state view toggle: `month` (default) and `schedule`. Active variant
  # renders as plain `label` in section-accent; inactive stays bracketed
  # `[label]`. Rendered via `Tui::ViewToggleComponent` in the title-actions
  # slot alongside `[ ] sync`.
  #
  # ## Filter chips
  #
  # Four chips above the grid: `channel`, `game`, `system`, `manual`.
  # Each chip uses server-side URL params: `?calendar_filter[channel]=on` etc.
  # No localStorage. Brackets paint in `var(--section-accent-home)`. Label
  # paints in the category accent color:
  #   - channel → `--section-accent-videos`
  #   - game    → `--section-accent-games`
  #   - system  → `--section-accent-home`
  #   - manual  → `--dracula-orange`
  #
  # ## Month grid
  #
  # 6-row max, Monday-first. Each day cell shows the day number top-left,
  # then `• short_title` bullets per entry, colored by category. Days
  # outside the current month are dimmed.
  #
  # ## Day detail dialog
  #
  # Enter on a focused day cell opens `Tui::CalendarDayDialogComponent`
  # showing that day's entries in a sessions-style table
  # (kind chip + title). Implemented via a `<button>` inside each cell
  # that calls `showModal()` on the matching `<dialog>`.
  #
  # ## Kwargs
  #
  # @param current_view [Symbol] `:month` (default) or `:schedule`
  # @param buckets [Hash{Date => Array<CalendarEntry>}] entries grouped by date
  # @param grid [Array<Date>] Monday-first grid of dates (from HomePanelData)
  # @param today [Date] today in install tz for "current day" highlight
  # @param year [Integer] current month year
  # @param month [Integer] current month number
  # @param raw_filter [Hash, nil] `params[:calendar_filter]` — nil = all on
  #
  # ## Cable channel
  #
  # `pito:home:calendar` — panel-scoped, canonical grammar.
  #
  # ## Focusables
  #
  # `calendar_sync` (sync indicator), `month` + `schedule` (view toggle),
  # `filter_channel` + `filter_game` + `filter_system` + `filter_manual`
  # (filter chips), then `day_<iso8601>` per day cell in grid order.
  #
  # ## TUI parity
  #
  # The Ratatui sibling reads `data-tui-panel-*` attrs + CABLE_CHANNEL
  # constant. Filter URL shape and focusable key list are the parity contract.
  class CalendarPanelComponent < ViewComponent::Base
    include Tui::PanelBase
    include CalendarHelper

    PANEL_NAME = :calendar

    VIEWS = [
      { name: :month,    label: "month" },
      { name: :schedule, label: "schedule" }
    ].freeze

    DEFAULT_VIEW = :month

    WEEK_DAYS = %w[mon tue wed thu fri sat sun].freeze

    CATEGORY_ORDER = %w[channel game system manual].freeze

    def initialize(
      current_view: DEFAULT_VIEW,
      buckets: nil,
      grid: nil,
      today: nil,
      year: nil,
      month: nil,
      raw_filter: nil
    )
      @current_view = current_view.to_sym
      unless VIEWS.any? { |v| v[:name] == @current_view }
        raise ArgumentError, "Pito::CalendarPanelComponent current_view must be one of #{VIEWS.map { |v| v[:name] }.inspect}, got #{@current_view.inspect}"
      end
      @buckets    = buckets || {}
      @grid       = grid || []
      @today      = today || Date.current
      @year       = year  || @today.year
      @month      = month || @today.month
      @raw_filter = raw_filter
    end

    attr_reader :current_view, :buckets, :grid, :today, :year, :month, :raw_filter

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: {})
    end

    def focusables
      day_keys = grid.map { |d| "day_#{d.iso8601}" }
      %w[calendar_sync month schedule filter_channel filter_game filter_system filter_manual] + day_keys
    end

    def views
      VIEWS
    end

    # Month heading: "may 2026"
    def month_heading
      Date.new(year, month, 1).strftime("%b %Y").downcase
    end

    # Array of week-day header strings (mon…sun)
    def week_day_headers
      WEEK_DAYS
    end

    # Grid sliced into rows of 7
    def grid_rows
      grid.each_slice(7).to_a
    end

    # Is the given date in the panel's current month?
    def current_month_date?(date)
      date.year == year && date.month == month
    end

    # Is the given date today?
    def today_date?(date)
      date == today
    end

    # Entries for a day cell (pre-bucketed)
    def day_entries(date)
      buckets[date] || []
    end

    # Is the given category chip currently on?
    def category_active?(category)
      panel_calendar_category_active?(category, raw_filter)
    end

    # Toggle href for a category chip
    def category_chip_href(category)
      panel_calendar_chip_href(category, raw_filter, current_params: {})
    end

    # i18n chip label
    def category_chip_label(category)
      I18n.t("tui.home.panels.calendar.filter.#{category}")
    end

    # CSS modifier class for a category
    def category_css_modifier(category)
      "cal-filter-chip--#{category}"
    end

    # Bullet CSS class for an entry in the day cell
    def entry_bullet_class(entry)
      "cal-day-bullet cal-day-bullet--#{panel_calendar_entry_category(entry)}"
    end

    # Truncated bullet text
    def bullet_text(entry)
      panel_calendar_bullet_text(entry)
    end

    # Dialog id for a day cell
    def day_dialog_id(date)
      "cal-day-dialog-#{date.iso8601}"
    end

    # CSS classes for a day cell
    def day_cell_classes(date)
      classes = [ "cal-day-cell" ]
      classes << "cal-day-cell--other-month" unless current_month_date?(date)
      classes << "cal-day-cell--today"       if today_date?(date)
      classes.join(" ")
    end
  end
end
