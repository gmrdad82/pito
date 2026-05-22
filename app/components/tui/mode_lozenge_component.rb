module Tui
  # Beta 4 — Phase F1 / Phase 2E. Mode lozenge for the bottom status bar.
  # Renders the current editor mode as a styled span, vim-style, opted into
  # the canonical Tui::Transitionable mixin for scramble-settle +
  # color-crossfade on mode transitions (normal ↔ insert ↔ command ↔ search).
  #
  # Kwargs:
  #   mode: (Symbol) — :normal, :insert, :command, :search. Defaults to
  #                    :normal for any unrecognised value.
  #
  # Color map (mirror in tui_mode_lozenge_controller.js):
  #   normal  → :muted   (neutral default)
  #   insert  → :accent  (home accent — purple)
  #   command → :accent  (same accent — `:` glyph context differentiates)
  #   search  → :success (Dracula green)
  #
  # Cable / event:
  #   No direct cable subscription. The colocated tui-mode-lozenge controller
  #   listens for the `tui:mode-changed` document event (broadcast by
  #   tui-cursor) and delegates the value + color swap to the colocated
  #   tui-transition outlet on the same span. The Bottom Status Bar
  #   controller no longer touches this lozenge.
  #
  # i18n: label text comes from `tui.mode.<mode>` (en.yml).
  class ModeLozengeComponent < ViewComponent::Base
    include Tui::Transitionable

    MODES = %i[normal insert command search].freeze
    DEFAULT_MODE = :normal

    COLORS = {
      normal:  :muted,
      insert:  :accent,
      command: :accent,
      search:  :success
    }.freeze

    # @param mode [Symbol] current editor mode — :normal, :insert, :command, :search
    def initialize(mode: DEFAULT_MODE)
      sym = (mode.to_sym rescue DEFAULT_MODE)
      @mode = MODES.include?(sym) ? sym : DEFAULT_MODE
    end

    attr_reader :mode

    def mode_word
      I18n.t("tui.mode.#{mode}", default: mode.to_s)
    end

    # Data-attrs for the lozenge host element. Layers:
    #   1. Transitionable mixin attrs (controller, color, value, align)
    #   2. Per-mode word data-attrs so the delegator controller can resolve
    #      the new mode's i18n label without a server round-trip
    def transitionable_data
      attrs = transitionable_attrs(
        value: mode_word,
        color: COLORS[mode]
      )
      attrs[:data].merge!(
        tui_mode_lozenge_normal_value:  I18n.t("tui.mode.normal",  default: "normal"),
        tui_mode_lozenge_insert_value:  I18n.t("tui.mode.insert",  default: "insert"),
        tui_mode_lozenge_command_value: I18n.t("tui.mode.command", default: "command"),
        tui_mode_lozenge_search_value:  I18n.t("tui.mode.search",  default: "search")
      )
      attrs
    end
  end
end
