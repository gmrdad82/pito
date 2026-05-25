module Pito
  # Pito::CalendarLegendComponent — inline legend row for calendar event-type categories.
  #
  # Renders a horizontal row of 4 colored-square + label items: one per
  # calendar category (channel / game / system / manual). Designed to sit
  # below or above the CalendarPanelComponent grid as a visual key.
  #
  # ## Interactivity
  #
  # Each legend item is a <button> that dispatches the
  # `pito:action:calendar_filter_category` custom event via the
  # `action-trigger` Stimulus controller. The payload `{ category: "…" }`
  # is embedded as `data-action-payload` and read by the listener that
  # handles the filter. No inline POST, no form, no href.
  #
  # ## Active filter
  #
  # When `active_filter:` matches a category symbol, that item receives a
  # bold/accented variant class (`cal-legend-item--active`) while the others
  # are rendered normally.
  #
  # ## Colors
  #
  # Color squares use CSS variables matching the calendar panel's category
  # color contract (see CalendarPanelComponent docblock). Colors are resolved
  # at render time via `Pito::Calendar::CategoryColors.for(category)` when
  # that service exists; otherwise the component falls back to an inline map
  # of the same values.
  #
  # ## Kwargs
  #
  # @param active_filter [Symbol, nil] currently-filtered category, or nil
  #   for no highlight. Valid values: :channel, :game, :system, :manual.
  #
  # ## Cable channel
  #
  # None — this is a pure-display sub-component. The parent
  # CalendarPanelComponent owns the cable subscription.
  #
  # ## Related
  #
  # - Pito::CalendarPanelComponent — parent panel
  # - Pito::Calendar::CategoryColors — canonical color source (C1 service)
  # - app/javascript/controllers/action_trigger_controller.js — Stimulus wiring
  # - CalendarHelper#PANEL_CALENDAR_CATEGORIES — category→entry_type mapping
  class CalendarLegendComponent < ViewComponent::Base
    CATEGORIES = %w[channel game system manual].freeze

    # Fallback inline color map mirrors the CSS variables declared in
    # app/assets/tailwind/_theme.css. Used when Pito::Calendar::CategoryColors
    # is not yet loaded (boot order / C1 service not yet defined).
    FALLBACK_COLORS = {
      "channel" => "var(--section-accent-videos)",
      "game"    => "var(--section-accent-games)",
      "system"  => "var(--section-accent-home)",
      "manual"  => "var(--dracula-orange)"
    }.freeze

    def initialize(active_filter: nil)
      @active_filter = active_filter&.to_sym
    end

    attr_reader :active_filter

    def categories
      CATEGORIES
    end

    # CSS color string for the category square. Tries the canonical service
    # first; falls back to the inline map so the component remains renderable
    # before C1 lands.
    def color_for(category)
      if defined?(Pito::Calendar::CategoryColors)
        Pito::Calendar::CategoryColors.for(category.to_sym)
      else
        FALLBACK_COLORS.fetch(category.to_s, "var(--color-muted)")
      end
    end

    # True when this category is the currently-active filter.
    def active?(category)
      active_filter == category.to_sym
    end

    # CSS classes for a legend item.
    def item_classes(category)
      base = "cal-legend-item cal-legend-item--#{category}"
      active?(category) ? "#{base} cal-legend-item--active" : base
    end

    # Lowercase human label. All 4 category names are plain English words —
    # no brand caps apply (per CLAUDE.md terminology).
    def label_for(category)
      I18n.t("tui.home.panels.calendar.legend.#{category}",
             default: category.to_s)
    end

    # Action name dispatched via the action-trigger Stimulus controller.
    # Consumers listening on `pito:action:calendar_filter_category` receive
    # `{ category: "channel"|"game"|"system"|"manual" }` in `event.detail`.
    ACTION_NAME = "calendar_filter_category"
  end
end
