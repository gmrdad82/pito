module Pito
  # Pito::HomeRowComponent — renders one horizontal row of the home dashboard,
  # distributing panel slots across a CSS grid.
  #
  # ## Purpose
  #
  # A generic row container used by the dashboard view (`dashboard/index.html.erb`)
  # when looping over `AppSetting.home_rows_config`. Each row declares its own
  # column count, optional fractional ratios, and the ordered list of panel
  # slots that fill those columns. The component resolves each slot to its
  # canonical ViewComponent class via PANEL_COMPONENT_MAP and forwards the
  # pre-assembled `panel_data` kwargs to it.
  #
  # ## kwargs
  #
  # - `cols:`        Integer 1–4 (required). Controls the CSS modifier class and
  #                  the number of expected slots.
  # - `panels:`      Array (required, length == cols). Each element is either:
  #                    - String  — a panel key, e.g. "calendar"
  #                    - Hash    — `{ "stack" => [key1, key2] }` for a vertical
  #                      stack of panels inside a single column slot.
  # - `ratios:`      Optional Array<Integer> (length == cols, values sum to 100).
  #                  Drives `grid-template-columns` as fractional units (fr).
  #                  Defaults to equal weighting (each slot = 1fr).
  # - `panel_data:`  Hash<String, Hash> mapping panel key → kwargs Hash that is
  #                  splatted into the resolved panel component's initializer.
  #                  Assembled by the `HomePanelData` concern in the controller.
  #                  Missing keys produce an empty Hash (safe no-op for panels
  #                  with no required args; panels that do require args will
  #                  raise at render time, which is intentional and fail-fast).
  #
  # ## Focusables
  #
  # None — the row itself is not a focusable unit. Focus is handled by each
  # child panel component individually.
  #
  # ## Cable channel
  #
  # None — row is a layout primitive. Cable subscriptions live in child panels.
  #
  # ## Related dependencies
  #
  # - `PANEL_COMPONENT_MAP` constant — exhaustive map from panel key to class
  #   name string. Constantize at render time so hot-reload works cleanly.
  # - `HomePanelData` concern (`app/controllers/concerns/home_panel_data.rb`) —
  #   assembles `panel_data` in the controller before the view renders.
  # - `AppSetting.home_rows_config` — the JSON config that the dashboard
  #   controller uses to instantiate rows and pass to this component.
  class HomeRowComponent < ViewComponent::Base
    # Maps panel key strings to their canonical component class name.
    # New panels: add an entry here. Keys must match AppSetting.home_rows_config
    # slot strings and the HomePanelData concern's data keys.
    PANEL_COMPONENT_MAP = {
      "channels_overview"  => "Pito::ChannelsOverviewPanelComponent",
      "latest_videos"      => "Pito::LatestVideosPanelComponent",
      "games_releasing"    => "Pito::GamesReleasingPanelComponent",
      "notifications_feed" => "Pito::NotificationsFeedPanelComponent",
      "calendar"           => "Pito::CalendarPanelComponent",
      "stack"              => "Pito::StackPanelComponent",
      "notifications"      => "Pito::NotificationsPanelComponent",
      "security"           => "Pito::SecurityPanelComponent"
    }.freeze

    attr_reader :cols, :panels, :ratios, :panel_data

    # @param cols       [Integer]        Number of columns (1–4).
    # @param panels     [Array]          Ordered slot descriptors (String or Hash).
    # @param ratios     [Array<Integer>] Optional column width ratios (sum = 100).
    # @param panel_data [Hash]           panel_key => kwargs forwarded to components.
    def initialize(cols:, panels:, ratios: nil, panel_data: {})
      @cols       = cols.to_i.clamp(1, 4)
      @panels     = panels
      @ratios     = ratios
      @panel_data = panel_data || {}
    end

    # Returns the inline `grid-template-columns` value, e.g. "40fr 60fr".
    # Falls back to equal-width columns when no ratios are supplied.
    def grid_template_columns
      if ratios.present? && ratios.length == cols
        ratios.map { |r| "#{r}fr" }.join(" ")
      else
        Array.new(cols, "1fr").join(" ")
      end
    end

    # Resolves a String slot key to a rendered component or unknown-panel markup.
    # Returns nil when the component class cannot be constantized.
    def component_class_for(key)
      class_name = PANEL_COMPONENT_MAP[key.to_s]
      return nil unless class_name

      class_name.constantize
    rescue NameError
      nil
    end

    # Returns the kwargs Hash for a given panel key, or an empty Hash.
    def kwargs_for(key)
      panel_data[key.to_s] || {}
    end
  end
end
