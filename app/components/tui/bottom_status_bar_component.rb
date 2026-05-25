module Tui
  # R10a (2026-05-25) — Bottom status bar. Sticky-bottom counterpart to
  # `Tui::TopStatusBarComponent`. Provides the current mode + breadcrumb
  # on the left, Sidekiq queue depth in the center, and help/command hints
  # on the right.
  #
  # Layout (3-zone grid `1fr auto 1fr`):
  #
  #   <mode> | <breadcrumb>    [sidekiq]    ? help  : command
  #
  # Children (all composed via `render` in the template):
  #   - `Tui::ModeLozengeComponent`  — mode lozenge (left, with scramble/color animation)
  #   - `Tui::BreadcrumbComponent`   — screen/panel/sub-panel crumb (left)
  #   - `Tui::SidekiqStatsComponent` — b/e/r queue cells (center)
  #   - `Tui::HelpHintComponent`     — `? help` hint (right)
  #   - `Tui::CommandHintComponent`  — `: command` hint (right)
  #
  # Kwargs:
  #   current_section: (String) — "home", "videos", or "games". Forwarded
  #                    to `Tui::BreadcrumbComponent` as the idle fallback screen name.
  #   mode:            (Symbol) — :normal, :insert, :command, :search. Forwarded
  #                    to `Tui::ModeLozengeComponent`. Defaults to :normal.
  #
  # The section accent (`--section-accent`) cascades via
  # `body[data-section]` (set by `current_section` in
  # `ApplicationHelper`), so the bar inherits the right color
  # automatically — no per-render section-to-color lookup needed.
  #
  # Cable: no direct subscription. Child VCs each manage their own
  # cable events (`tui:mode-changed`, `tui:sidekiq-changed`,
  # `tui:panel-focus-changed`).
  #
  # CABLE_CHANNEL: none (child VCs own their subscriptions)
  # Focusables: none (chrome bar, not a panel)
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
