module Tui
  # Beta 4 — Phase 2D wires the breadcrumb segment of the top status bar
  # through the canonical Tui::Transitionable mixin so panel / sub-panel
  # navigation gets scramble-settle + color-crossfade for free.
  #
  # Visual contract:
  #   - Single tui-transition host (`<span class="sb-section">`). The
  #     legacy 4-span structure (.sb-section__panel, .sb-section__sub-panel,
  #     .sb-section__sub-panel-paren) is dropped — the transition
  #     controller's replaceCells wipes inner DOM on every diff so per-zone
  #     spans cannot survive. Per-zone color is sacrificed for canonical
  #     scramble + crossfade; if multi-zone color is later required, add
  #     it as a separate feature to tui-transition.
  #   - color: :muted when no panel focused; :accent when a panel is in
  #     focus. The tui-transition controller resolves color names to the
  #     palette via its detectKind() pipeline (.sb-section currently has
  #     no kind class — caller stylesheet owns the actual colors).
  #
  # Format (mirrored 1:1 in tui_breadcrumb_controller.js):
  #   - screen only             → "home"
  #   - screen + panel          → "home security"
  #   - screen + panel + sub    → "home security:(notifications)"
  #
  # Constructor inputs:
  #   - screen:    required string ("home", "videos", "games", ...).
  #   - panel:     optional string. When present, becomes part of the SSR
  #                paint; Stimulus then patches via tui:panel-focus-changed.
  #   - sub_panel: optional string. Only renders alongside panel.
  #
  # The component honors the `data-tui-status-bar-target="section"`
  # contract so `tui_status_bar_controller.js`'s seedSectionFromFocusedPanel
  # + handlePanelFocus keep working unchanged.
  class BreadcrumbComponent < ViewComponent::Base
    include Tui::Transitionable

    def initialize(screen:, panel: nil, sub_panel: nil)
      @screen = screen.to_s
      @panel = panel.presence&.to_s
      @sub_panel = sub_panel.presence&.to_s
    end

    attr_reader :screen, :panel, :sub_panel

    # Mirror of the JS formatter in tui_breadcrumb_controller.js#format.
    # Kept here as a class method so specs + Ruby callers can derive the
    # same string the Stimulus controller will compute client-side.
    def self.format(screen, panel, sub_panel)
      screen = screen.to_s
      panel = panel.to_s if panel
      sub_panel = sub_panel.to_s if sub_panel
      return screen if panel.nil? || panel.empty?
      return "#{screen} #{panel}" if sub_panel.nil? || sub_panel.empty?

      "#{screen} #{panel}:(#{sub_panel})"
    end

    def current_value
      self.class.format(@screen, @panel, @sub_panel)
    end

    def color_for_state
      @panel.present? ? :accent : :muted
    end

    def transitionable_data
      transitionable_attrs(value: current_value, color: color_for_state)
    end
  end
end
