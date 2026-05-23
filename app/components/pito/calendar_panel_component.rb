module Pito
  # Pito::CalendarPanelComponent — home-screen panel showing the
  # publication / release calendar with scheduled video drops,
  # cross-channel conflicts, and game-release overlay.
  #
  # ## View toggle
  #
  # The panel exposes a two-state view toggle in the title-actions
  # slot (right-edge of the top border, mirroring the Meilisearch
  # sub-panel's `[reindex]` placement):
  #
  #   - `month`    — default, calendar grid (TBD body)
  #   - `schedule` — schedule list (TBD body)
  #
  # The toggle uses `Tui::ViewToggleComponent` with width-stable
  # active/inactive variants (`[label]` inactive, ` label ` active —
  # both render at `label.length + 2` cols so the panel chrome stays
  # still on toggle). Inactive renders in section-accent (matches
  # the bracketed-action family); active renders in `--color-success`
  # (Dracula green) — distinct from the accent color per the locked
  # design (accent was noted to collide).
  #
  # ## Round status
  #
  # Calendar toggle round: renders the toggle in the title-actions
  # slot and a `[ <view> view TBD ]` placeholder body inside
  # `Tui::PanelFieldsetComponent`. Real per-view content (week / month
  # calendar grid + conflict highlighting via
  # `Pito::Schedule::Conflict`) lands in a future content round per
  # `docs/architecture.md` § Home panels.
  #
  # ## Canonical wiring
  #
  # - Includes `Tui::PanelBase` for the `panel_root_data` Hash spread
  #   into the section content_tag (controller / cursor target / cable
  #   screen+name values / focusables / keybinds).
  # - Cable channel: `pito:home:calendar` (canonical grammar).
  # - Focusables: `month` + `schedule` (the toggle buttons are
  #   keyboard-cursorable per design.md keyboard-only rule).
  #
  # ## TUI parity
  #
  # The Ratatui sibling component reads the same panel data attrs +
  # the same toggle pattern (` view ` active / `[view]` inactive,
  # both `label.length + 2` columns) — see
  # `Tui::ViewToggleComponent` docblock for the parity contract.
  #
  # ## Kwargs
  #
  # @param current_view [Symbol] active view — `:month` (default) or
  #   `:schedule`. The view is server-derived on initial render and
  #   updated client-side via the `tui-view-toggle` Stimulus
  #   controller's CustomEvent (parent listener TBD in a follow-up
  #   round when the per-view body content lands).
  class CalendarPanelComponent < ViewComponent::Base
    include Tui::PanelBase

    PANEL_NAME = :calendar

    VIEWS = [
      { name: :month,    label: "month" },
      { name: :schedule, label: "schedule" }
    ].freeze

    DEFAULT_VIEW = :month

    def initialize(current_view: DEFAULT_VIEW)
      @current_view = current_view.to_sym
      unless VIEWS.any? { |v| v[:name] == @current_view }
        raise ArgumentError, "Pito::CalendarPanelComponent current_view must be one of #{VIEWS.map { |v| v[:name] }.inspect}, got #{@current_view.inspect}"
      end
    end

    attr_reader :current_view

    def title
      I18n.t("tui.home.panels.#{PANEL_NAME}.title")
    end

    def panel_data
      panel_root_data(name: PANEL_NAME, focusables: focusables, keybinds: {})
    end

    def focusables
      %w[month schedule]
    end

    def views
      VIEWS
    end
  end
end
