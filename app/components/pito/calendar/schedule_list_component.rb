module Pito
  module Calendar
    # Pito::Calendar::ScheduleListComponent — Google-Calendar-list-style
    # schedule view for the home Calendar panel's "schedule" toggle state.
    #
    # ## Purpose
    #
    # Renders upcoming CalendarEntry rows grouped by date. Only dates that
    # have at least one entry produce a row group — empty dates are skipped
    # (matching Google Calendar list mode). Within each group, entries are
    # ordered as supplied (caller must pass entries ordered ascending by
    # `starts_at`).
    #
    # ## Row structure
    #
    # Each date group:
    #   [date header]  "<Mon, May 26>"  — muted, full weekday+month+day
    #   [entry row]    "<HH:MM>  ■  <title>  <category-label>"
    #
    # Time column: HH:MM (24h) in install timezone. "all-day" when
    # `entry.all_day` is truthy. Category label is the category symbol
    # rendered muted after the title.
    #
    # ## Category color square
    #
    # An 8×8 px filled `<span>` inline-styled with the hex color from
    # `Pito::Calendar::CategoryColors.for(entry.category)` if that module
    # is available. Falls back to FALLBACK_CATEGORY_COLORS if the C1 module
    # has not been loaded yet (parallel delivery safety).
    #
    # ## Kwargs
    #
    # @param entries [CalendarEntry::Relation, Array<CalendarEntry>]
    #   Entries ordered ascending by `starts_at` / `occurs_at`. The component
    #   does NOT re-sort; the caller is responsible for ordering.
    # @param range_start [Date] First date of the visible window.
    #   Defaults to `Date.current`.
    # @param range_end [Date] Last date (inclusive) of the visible window.
    #   Defaults to `range_start + 30 days`.
    # @param category_filter [Symbol, nil] When present, only entries whose
    #   `#category` matches this symbol are rendered. nil = all categories.
    #
    # ## URL state
    #
    # Range navigation is driven by `?range_start=YYYY-MM-DD&range_end=YYYY-MM-DD`
    # query params — set by the Calendar controller. This component is
    # read-only with respect to navigation; it renders whatever range the
    # controller resolved.
    #
    # ## No-events copy
    #
    # When the filtered entry list is empty: "no events in the next N days"
    # where N = `(range_end - range_start).to_i`. Rendered muted.
    #
    # ## Cable channel
    #
    # Inherits `pito:home:calendar` from the parent `Pito::CalendarPanelComponent`.
    # This sub-component does not subscribe independently.
    #
    # ## Focusables
    #
    # Each entry row is focusable via `sched_entry_<entry.id>`.
    # Exposed via `#focusables` for TUI parity.
    #
    # ## Related
    #
    # - `Pito::CalendarPanelComponent` — parent panel
    # - `Pito::Calendar::CategoryColors` — canonical category hex map (C1)
    # - `CalendarHelper` — `entry_time_label`, `entry_date_grouping_label`
    class ScheduleListComponent < ViewComponent::Base
      include CalendarHelper

      # Fallback category colors used when Pito::Calendar::CategoryColors
      # is not yet available (C1 parallel delivery safety).
      FALLBACK_CATEGORY_COLORS = {
        channel: "#22c55e",
        game:    "#3b82f6",
        system:  "#f59e0b",
        manual:  "#6b7280"
      }.freeze

      def initialize(
        entries:,
        range_start: nil,
        range_end: nil,
        category_filter: nil
      )
        @range_start     = range_start || Date.current
        @range_end       = range_end   || @range_start + 30
        @category_filter = category_filter&.to_sym
        @raw_entries     = entries
      end

      attr_reader :range_start, :range_end, :category_filter

      # Focusable key list for TUI parity. Each entry row is individually
      # focusable.
      def focusables
        filtered_entries.map { |e| "sched_entry_#{e.id}" }
      end

      # Entries after applying the optional category_filter. Materialized
      # once per render via memoization.
      def filtered_entries
        @filtered_entries ||= begin
          list = @raw_entries.to_a
          if category_filter
            list.select { |e| e.category == category_filter }
          else
            list
          end
        end
      end

      # True when there are no entries to display.
      def empty?
        grouped_entries.empty?
      end

      # No-events muted copy. N = range window in whole days.
      def empty_message
        n = (range_end - range_start).to_i
        I18n.t("tui.home.panels.calendar.schedule.no_events", count: n,
               default: "no events in the next #{n} days")
      end

      # Entries grouped by calendar date (in install tz), preserving the
      # ascending order supplied by the caller. Only dates with >= 1 entry
      # appear — empty dates are skipped.
      #
      # Returns an Array of [Date, Array<CalendarEntry>] pairs ordered by date.
      def grouped_entries
        @grouped_entries ||= begin
          tz = install_timezone
          filtered_entries
            .group_by { |e| e.starts_at.in_time_zone(tz).to_date }
            .sort_by { |date, _| date }
        end
      end

      # Date header label in "Mon, May 26" format (title-cased, not lowercased,
      # to match Google Calendar list visual — prominent day label).
      def date_header_label(date)
        date.strftime("%a, %b %-d")
      end

      # Time column for a single entry: HH:MM (24h) or "all-day".
      def entry_time(entry)
        return "all-day" if entry.all_day

        tz = install_timezone
        entry.starts_at.in_time_zone(tz).strftime("%H:%M")
      end

      # Inline style string for the 8×8 category color square.
      def color_square_style(entry)
        hex = category_hex(entry.category)
        "display:inline-block;width:8px;height:8px;background:#{hex};flex-shrink:0;"
      end

      # Human-readable category label (muted, after title).
      def category_label(entry)
        entry.category.to_s
      end

      # Focusable data-key for a single entry row.
      def entry_focusable_key(entry)
        "sched_entry_#{entry.id}"
      end

      private

      def install_timezone
        Rails.application.config.x.pito.timezone
      end

      # Resolve hex color for a category symbol. Prefers the canonical
      # Pito::Calendar::CategoryColors module (C1); falls back to the
      # inline FALLBACK_CATEGORY_COLORS constant.
      def category_hex(category)
        if defined?(Pito::Calendar::CategoryColors)
          Pito::Calendar::CategoryColors.for(category)
        else
          FALLBACK_CATEGORY_COLORS.fetch(category.to_sym, "#6b7280")
        end
      end
    end
  end
end
