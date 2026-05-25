module Pito
  # Pito::CalendarPanelComponent — home-screen calendar panel.
  #
  # Renders the calendar legend always at top, then branches on `mode:` to
  # compose either `Pito::Calendar::MonthGridComponent` (month grid view,
  # default) or `Pito::Calendar::ScheduleListComponent` (schedule list view).
  # The view toggle in the title-border slot uses URL query param
  # `?calendar_mode=month|list` — clicking an inactive mode action sends a GET
  # to `Pito::CalendarController#set_mode` which redirects to `/` with the param
  # persisted. This follows the "no localStorage" hard rule.
  #
  # ## View toggle — title-border slot
  #
  # Follows the bracket-to-space rule: active mode renders as a plain space-
  # delimited label (no brackets); inactive mode renders as bracketed action.
  # Both paint in `var(--section-accent)` (actions-always-accent rule).
  #
  # Title slot copy: `calendar month [list]` (when month is active) or
  # `calendar [month] list` (when list is active).
  #
  # ## Filter chips (category)
  #
  # Four chips above the sub-component: `channel`, `game`, `system`, `manual`.
  # Each chip uses a server-side URL param: `?calendar_category=<cat>` (single
  # active category; empty = all). Wired via `Pito::CalendarController#filter_category`.
  #
  # ## Kwargs
  #
  # @param mode [Symbol] `:month` (default) or `:list`
  # @param entries [Array<CalendarEntry>] flat entry array for the current month window
  # @param buckets [Hash{Date => Array<CalendarEntry>}] entries grouped by date (legacy; kept for compat)
  # @param grid [Array<Date>] Monday-first grid of dates (from HomePanelData)
  # @param today [Date] today in install tz for "current day" highlight
  # @param year [Integer] current month year
  # @param month [Integer] current month number
  # @param raw_filter [Hash, nil] `params[:calendar_filter]` — nil = all on
  # @param category [Symbol, nil] single category filter from `?calendar_category=` param
  #
  # ## Cable channel
  #
  # `pito:home:calendar` — panel-scoped, canonical grammar.
  #
  # ## Focusables
  #
  # `calendar_sync` (sync indicator), `month` + `list` (mode toggle actions),
  # `filter_channel` + `filter_game` + `filter_system` + `filter_manual`
  # (filter chips), then `day_<iso8601>` per day cell in grid order.
  #
  # ## Palette commands (`panel_commands`)
  #
  # 7 commands registered: switch to month mode, switch to list mode, filter
  # by channel / game / system / manual, clear filter. All scope: :home.
  #
  # ## TUI parity
  #
  # The Ratatui sibling reads `data-tui-panel-*` attrs + CABLE_CHANNEL
  # constant. Filter URL shape and focusable key list are the parity contract.
  class CalendarPanelComponent < ViewComponent::Base
    include Tui::PanelBase
    include CalendarHelper

    PANEL_NAME = :calendar

    CABLE_CHANNEL = "pito:home:calendar".freeze

    MODES = %i[month list].freeze
    DEFAULT_MODE = :month

    VIEWS = [
      { name: :month, label: "month" },
      { name: :list,  label: "list" }
    ].freeze

    WEEK_DAYS = %w[mon tue wed thu fri sat sun].freeze

    CATEGORY_ORDER = %w[channel game system manual].freeze

    def initialize(
      mode: DEFAULT_MODE,
      entries: nil,
      buckets: nil,
      grid: nil,
      today: nil,
      year: nil,
      month: nil,
      raw_filter: nil,
      category: nil,
      # Legacy alias kept for any call sites still passing current_view:
      current_view: nil
    )
      resolved = (current_view || mode).to_sym
      @mode = MODES.include?(resolved) ? resolved : DEFAULT_MODE
      @entries    = entries || (buckets ? buckets.values.flatten : [])
      @buckets    = buckets || {}
      @grid       = grid || []
      @today      = today || Date.current
      @year       = year  || @today.year
      @month      = month || @today.month
      @raw_filter = raw_filter
      @category   = category&.to_sym
    end

    attr_reader :mode, :entries, :buckets, :grid, :today, :year, :month, :raw_filter, :category

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: {})
    end

    def focusables
      day_keys = grid.map { |d| "day_#{d.iso8601}" }
      %w[calendar_sync month list filter_channel filter_game filter_system filter_manual] + day_keys
    end

    def views
      VIEWS
    end

    # Current mode as string (for URL params and CSS).
    def current_mode_str
      mode.to_s
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
    def category_active?(cat)
      panel_calendar_category_active?(cat, raw_filter)
    end

    # Toggle href for a category chip
    def category_chip_href(cat)
      panel_calendar_chip_href(cat, raw_filter, current_params: {})
    end

    # i18n chip label
    def category_chip_label(cat)
      I18n.t("tui.home.panels.calendar.filter.#{cat}")
    end

    # CSS modifier class for a category
    def category_css_modifier(cat)
      "cal-filter-chip--#{cat}"
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

    # Phase C4 — `:` palette commands for the calendar panel.
    # 7 commands: 2 mode-switch + 4 category filters + 1 clear filter.
    # All scope: :home — calendar is a home-screen panel only.
    def panel_commands
      [
        { key: "calendar_set_mode_month",
          name: I18n.t("tui.commands.calendar_set_mode_month.name"),
          hint: I18n.t("tui.commands.calendar_set_mode_month.hint"),
          action_name: :calendar_set_mode,
          args: { mode: "month" } },
        { key: "calendar_set_mode_list",
          name: I18n.t("tui.commands.calendar_set_mode_list.name"),
          hint: I18n.t("tui.commands.calendar_set_mode_list.hint"),
          action_name: :calendar_set_mode,
          args: { mode: "list" } },
        { key: "calendar_filter_channel",
          name: I18n.t("tui.commands.calendar_filter_channel.name"),
          hint: I18n.t("tui.commands.calendar_filter_channel.hint"),
          action_name: :calendar_filter_category,
          args: { category: "channel" } },
        { key: "calendar_filter_game",
          name: I18n.t("tui.commands.calendar_filter_game.name"),
          hint: I18n.t("tui.commands.calendar_filter_game.hint"),
          action_name: :calendar_filter_category,
          args: { category: "game" } },
        { key: "calendar_filter_system",
          name: I18n.t("tui.commands.calendar_filter_system.name"),
          hint: I18n.t("tui.commands.calendar_filter_system.hint"),
          action_name: :calendar_filter_category,
          args: { category: "system" } },
        { key: "calendar_filter_manual",
          name: I18n.t("tui.commands.calendar_filter_manual.name"),
          hint: I18n.t("tui.commands.calendar_filter_manual.hint"),
          action_name: :calendar_filter_category,
          args: { category: "manual" } },
        { key: "calendar_filter_clear",
          name: I18n.t("tui.commands.calendar_filter_clear.name"),
          hint: I18n.t("tui.commands.calendar_filter_clear.hint"),
          action_name: :calendar_filter_category,
          args: { category: "" } }
      ] + sync_pause_commands("home.calendar", label: "calendar")
    end
  end
end
