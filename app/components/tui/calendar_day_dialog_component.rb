module Tui
  # Tui::CalendarDayDialogComponent — day-detail dialog for the home Calendar panel.
  #
  # Opens via Enter on a focused day cell in `Pito::CalendarPanelComponent`.
  # Renders a table of the day's CalendarEntry rows:
  #   kind chip (category) | title text
  #
  # Uses `Tui::DialogComponent` for chrome (border, title, Esc hint).
  # Screen accent is `:home` (calendar lives on home).
  #
  # ## Kwargs
  #
  # @param id [String] DOM id for the `<dialog>` element (must match the
  #   `showModal()` call in the day cell button). Required.
  # @param date [Date] the day this dialog represents. Used for the title.
  # @param entries [Array<CalendarEntry>] entries for this day, ordered by
  #   created_at ASC (pre-sorted by the controller). Empty array is fine —
  #   the dialog renders an empty-state hint.
  #
  # ## Focusables
  #
  # None inside the dialog itself — the day-detail view is read-only.
  # The cursor controller manages Esc-to-close via the canonical dialog
  # open/close MutationObserver.
  #
  # ## Cable channel
  #
  # None — this dialog is ephemeral; it reads the pre-fetched entries
  # passed from `Pito::CalendarPanelComponent`. Cable broadcasts that update
  # the panel buckets will re-render the parent; the dialog re-fetches on
  # next open.
  #
  # ## Related
  #
  # `Pito::CalendarPanelComponent` — parent panel that renders this dialog
  # `Tui::DialogComponent`         — chrome primitive
  class CalendarDayDialogComponent < ViewComponent::Base
    # Category-to-CSS modifier map for the kind chip.
    CATEGORY_CSS = {
      "channel" => "cal-day-dialog__kind--channel",
      "game"    => "cal-day-dialog__kind--game",
      "system"  => "cal-day-dialog__kind--system",
      "manual"  => "cal-day-dialog__kind--manual"
    }.freeze

    def initialize(id:, date:, entries:)
      @id      = id
      @date    = date
      @entries = entries || []
    end

    attr_reader :id, :date, :entries

    def dialog_title
      date.strftime("%-d %b %Y").downcase
    end

    def empty?
      entries.empty?
    end

    # Category label for an entry (used as kind chip text).
    def entry_category(entry)
      case entry.entry_type
      when "channel_published", "video_published", "video_scheduled" then "channel"
      when "game_release", "purchase_planned"                         then "game"
      when "milestone_auto"                                           then "system"
      else                                                                 "manual"
      end
    end

    def entry_kind_class(entry)
      CATEGORY_CSS.fetch(entry_category(entry), "cal-day-dialog__kind--manual")
    end
  end
end
