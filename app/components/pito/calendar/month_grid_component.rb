module Pito
  module Calendar
    # Pito::Calendar::MonthGridComponent — standalone Google-Calendar-style
    # month grid, extracted from `Pito::CalendarPanelComponent` for
    # reuse across Turbo Stream navigation responses.
    #
    # Renders a full 6-row × 7-col Sunday-first grid for a given month
    # with per-day event chips, "today" highlight, outside-month dimming,
    # category color dots, and navigation actions in the title-border slot.
    #
    # ## Title-border slot
    #
    # `<month_name> <year>  [prev] today [next] [year]`
    #
    #   - Month/year label: `var(--color-muted)` (label role)
    #   - Action brackets (`[prev]`, `[next]`, `[year]`): `var(--section-accent)`
    #   - `today` between `[prev]` and `[next]`: plain space-delimited label
    #     (not bracketed — non-action chrome per bracket-to-space rule)
    #
    # ## Day grid
    #
    # 6 rows × 7 cols. Sunday first (WEEK_DAYS order). Each day cell:
    #   - Day number top-left in `var(--color-muted)` for outside-month,
    #     `var(--color-text)` for current-month.
    #   - Today cell: `border: 1px solid var(--section-accent)`.
    #   - Up to 3 event chips (more entries → "+N more" muted hint).
    #   - Event chip: 8×8 square colored with `Pito::Calendar::CategoryColors.for`
    #     + truncated title (12 chars max) in `var(--color-muted)`.
    #
    # ## Category filter
    #
    # Optional `category_filter:` kwarg (Symbol or nil). When non-nil
    # only entries matching the given category are rendered in day cells.
    # Filtering is applied in Ruby (the `entries:` relation/array is
    # already loaded); no SQL is re-issued.
    #
    # ## Navigation actions
    #
    # [prev] → `/pito/calendar/prev?month=YYYY-MM` (GET, Turbo Frame)
    # [next] → `/pito/calendar/next?month=YYYY-MM` (GET, Turbo Frame)
    # today  → `/pito/calendar/today` (muted label, not bracketed)
    # [year] → `/pito/calendar/pick_year` (GET, Turbo Frame)
    #
    # All navigation links target `#pito_calendar_panel` Turbo Frame,
    # replacing the month grid with the next month's rendered grid.
    #
    # ## Cable channel
    #
    # `pito:home:calendar` — inherits from the parent calendar panel.
    #
    # ## Kwargs
    #
    # @param entries [ActiveRecord::Relation, Array<CalendarEntry>] entries
    #   to display. The component buckets them by date in Ruby.
    # @param month [Date] first-of-month date for the displayed grid.
    #   Must be a Date; the component derives year/month from it.
    # @param today [Date] today's date for the "today" cell highlight.
    #   Defaults to `Date.current`.
    # @param category_filter [Symbol, nil] if set, only entries whose
    #   `panel_calendar_entry_category` matches are shown. nil = all.
    #
    # ## Focusables
    #
    # `mgrid_prev`, `mgrid_today`, `mgrid_next`, `mgrid_year`,
    # then `mgrid_day_<iso8601>` per day in grid order.
    #
    # ## Related
    #
    # `Pito::CalendarPanelComponent` — parent panel that embeds this grid.
    # `Pito::Calendar::CategoryColors` — category → hex color map.
    # `Pito::Calendar::CalendarController` — responds to nav actions.
    class MonthGridComponent < ViewComponent::Base
      include CalendarHelper

      WEEK_DAYS     = %w[sun mon tue wed thu fri sat].freeze
      CHIP_MAX_SHOW = 3
      CHIP_TITLE_MAX_CHARS = 12

      # @param entries [ActiveRecord::Relation, Array<CalendarEntry>]
      # @param month [Date] first-of-month
      # @param today [Date]
      # @param category_filter [Symbol, nil]
      def initialize(entries:, month:, today: nil, category_filter: nil)
        @month           = month.is_a?(Date) ? month : Date.parse(month.to_s)
        @today           = today || Date.current
        @category_filter = category_filter&.to_sym
        @raw_entries     = entries
      end

      attr_reader :month, :today, :category_filter

      # Year of the displayed month.
      def year
        @month.year
      end

      # Month number (1-12).
      def month_number
        @month.month
      end

      # Heading: "may 2026" — lowercase, muted role.
      def month_heading
        @month.strftime("%b %Y").downcase
      end

      # ISO string representation for the displayed month: "YYYY-MM".
      def month_param
        @month.strftime("%Y-%m")
      end

      # Prev-month date object.
      def prev_month_date
        @prev_month_date ||= (@month - 1.month).beginning_of_month
      end

      # Next-month date object.
      def next_month_date
        @next_month_date ||= (@month + 1.month).beginning_of_month
      end

      # Sunday-first 6×7 grid of Date objects for the month.
      def grid
        @grid ||= build_grid
      end

      # Grid sliced into rows of 7 for iteration.
      def grid_rows
        grid.each_slice(7).to_a
      end

      # Week-day header labels (sun…sat).
      def week_day_headers
        WEEK_DAYS
      end

      # Is the given date in the displayed month?
      def current_month_date?(date)
        date.year == year && date.month == month_number
      end

      # Is the given date today?
      def today_date?(date)
        date == today
      end

      # Entries for a specific day cell after category filtering.
      def day_entries(date)
        all = @buckets[date] || []
        return all if category_filter.nil?
        all.select { |e| panel_calendar_entry_category(e).to_sym == category_filter }
      end

      # Chips shown in the day cell (up to CHIP_MAX_SHOW).
      def visible_chips(date)
        day_entries(date).first(CHIP_MAX_SHOW)
      end

      # Overflow count shown as "+N more". Returns 0 when all chips fit.
      def overflow_count(date)
        total = day_entries(date).size
        total > CHIP_MAX_SHOW ? total - CHIP_MAX_SHOW : 0
      end

      # Hex background color for a chip based on its entry category.
      def chip_color(entry)
        Pito::Calendar::CategoryColors.for(panel_calendar_entry_category(entry))
      end

      # Truncated chip title (max CHIP_TITLE_MAX_CHARS chars + ellipsis).
      def chip_title(entry)
        raw = entry.title.to_s
        raw.length <= CHIP_TITLE_MAX_CHARS ? raw : "#{raw[0...CHIP_TITLE_MAX_CHARS]}…"
      end

      # CSS classes for a day cell.
      def day_cell_classes(date)
        classes = [ "mgrid-day-cell" ]
        classes << "mgrid-day-cell--other-month" unless current_month_date?(date)
        classes << "mgrid-day-cell--today"       if today_date?(date)
        classes.join(" ")
      end

      # Navigation href for [prev].
      def prev_month_href
        "/pito/calendar/prev?month=#{prev_month_date.strftime('%Y-%m')}"
      end

      # Navigation href for [next].
      def next_month_href
        "/pito/calendar/next?month=#{next_month_date.strftime('%Y-%m')}"
      end

      # Navigation href for today reset.
      def today_href
        "/pito/calendar/today"
      end

      # Navigation href for year picker.
      def pick_year_href
        "/pito/calendar/pick_year"
      end

      private

      # Build Sunday-first grid; starts on the Sunday on or before the
      # 1st of the month, ends after a complete 6-row grid.
      def build_grid
        first = Date.new(year, month_number, 1)
        # wday: 0=Sun … 6=Sat
        grid_start = first - first.wday.days
        Array.new(42) { |i| grid_start + i.days }
      end

      # Bucket all (optionally filtered) entries by date on first access.
      def before_render
        install_tz = Rails.application.config.x.pito.timezone
        entries    = Array(@raw_entries)
        @buckets   = entries.group_by { |e| e.starts_at.in_time_zone(install_tz).to_date }
      end
    end
  end
end
