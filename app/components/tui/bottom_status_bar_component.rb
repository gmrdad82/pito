module Tui
  # Beta 4 — Phase F1. Bottom status bar. Sticky-bottom counterpart to
  # `Tui::TopStatusBarComponent`. Provides the 3-screen nav, current mode
  # lozenge, and `?` / `:` keybinding hints, vim/TUI status-line style.
  #
  # Layout:
  #
  #   <mode> | home videos games | ? help  : command
  #
  # Children (all composed via `render` in the template):
  #   - `Tui::ModeLozengeComponent`  — mode lozenge (left)
  #   - `Tui::ScreensListComponent`  — screen nav row (center)
  #   - `Tui::HelpHintComponent`     — `? help` hint (right)
  #   - `Tui::CommandHintComponent`  — `: command` hint (right)
  #
  # Kwargs:
  #   current_section: (String) — "home", "videos", or "games". Forwarded
  #                    to `Tui::ScreensListComponent`.
  #   mode:            (Symbol) — :normal, :insert, :command, :search. Forwarded
  #                    to `Tui::ModeLozengeComponent`. Defaults to :normal.
  #
  # C18 (2026-05-21): settings consolidated into / (home). The sections
  # list was trimmed from 8 entries to 3 (home / videos / games).
  # /settings now redirects 301 to /.
  #
  # The section accent (`--section-accent`) cascades via
  # `body[data-section]` (set by `current_section` in
  # `ApplicationHelper`), so the bar inherits the right color
  # automatically — no per-render section-to-color lookup needed.
  class BottomStatusBarComponent < ViewComponent::Base
    MODES = %i[normal insert command search].freeze

    # @param current_section [String] active screen slug — "home", "videos", "games"
    # @param mode            [Symbol] editor mode — :normal, :insert, :command, :search
    def initialize(current_section:, mode: :normal)
      @current_section = current_section.to_s
      @mode = MODES.include?(mode.to_sym) ? mode.to_sym : :normal
    end

    attr_reader :current_section, :mode

    def pipe_label
      t("tui.bst.pipe")
    end
  end
end
