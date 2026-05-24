module Tui
  # Tui::SyncIndicatorComponent — checkbox-style sync indicator.
  #
  # 2026-05-24 (Phase 1D) — unified replacement for the now-deleted
  # `Tui::PauseControlComponent`. Renders the same `[ ] sync` / `[x] sync`
  # / `[!] sync` checkbox+word display in TWO contexts:
  #
  #   1. `mode: :tst` (default) — aggregate read-only indicator in the
  #      top status bar. Not clickable. Reflects global cable activity
  #      across every enabled target.
  #
  #   2. `mode: :target` — interactive per-panel / per-sub-panel control
  #      mounted in a panel or sub-panel's title-actions slot. Clicking
  #      toggles a `pito.sync.<target>` localStorage flag between "yes"
  #      (enabled, default) and "no" (disabled). Disabling a panel-level
  #      target suppresses cable broadcasts for every descendant
  #      sub-panel; disabling a sub-panel target suppresses that target
  #      alone.
  #
  # ## Five canonical states (locked 2026-05-24)
  #
  # | State        | Glyph | Color           | Shimmer | When                                                            |
  # |--------------|-------|-----------------|---------|-----------------------------------------------------------------|
  # | idle         | [ ]   | accent          | no      | Self-flag = "no", or no enabled targets / no activity.          |
  # | active       | [x]   | accent          | no      | Enabled + has active work (Sidekiq busy/enqueued/retry > 0).    |
  # | syncing      | [x]   | accent          | yes     | THIS target currently receiving cable content (shimmer on word) |
  # | mixed        | [-]   | accent          | no      | Parent panel state when its sub-panels have MIXED self-flags.   |
  # | disconnected | [!]   | danger (red)    | no      | Cable connection failed / syncing not available.                |
  #
  # 2026-05-24 lock update — "actions are always accent": every state
  # except `:disconnected` (which is the documented red exception) reads
  # in section-accent. The previous `:idle` muted color was wrong per
  # the new design rule and has been promoted to accent.
  #
  # `:mixed` (`[-]` glyph, accent) — parent panel only. A parent sync VC
  # shows `[-]` when its sub-panels have a mix of "yes" / "no" self
  # flags. Toggling the parent bulk-writes children to a uniform state
  # (the click handler propagates).
  #
  # ## Kwargs
  #
  # @param mode [Symbol] `:tst` (default) or `:target`.
  # @param state [Symbol] SSR initial state: one of
  #   `:idle`, `:active`, `:syncing`, `:disconnected`. Defaults to `:idle`.
  #   In `:target` mode the JS controller recomputes from localStorage on
  #   connect, so this is paint-only.
  # @param target [String, Symbol] (only `:target` mode) dot-namespaced
  #   target key, e.g. `"home.stack"` or `"home.stack.meilisearch"`. Used
  #   as the localStorage suffix: `pito.sync.<target>`. Value `"yes"` =
  #   enabled (default), `"no"` = disabled.
  # @param parent_target [String, Symbol, nil] (only `:target` mode)
  #   dot-namespaced target of the containing panel for sub-panels (e.g.
  #   `"home.stack"`). The JS controller resolves the displayed state by
  #   combining the self flag with the parent flag — a parent disabled
  #   target cascades to all sub-panels.
  # @param focusable_key [String, Symbol, nil] (only `:target` mode) when
  #   present, emits `data-tui-focusable=<key>` so j/k cursor can land on
  #   it. Style = `action`.
  #
  # ## Cable contract (`:tst` mode)
  #
  # Listens for `tui:cable-activity` and `tui:sync-changed` on document,
  # plus per-panel `pito:panel:*:received` / `pito:panel:*:connected` /
  # `pito:panel:*:disconnected` events. The controller derives idle /
  # active / syncing / disconnected from the combined signal.
  #
  # ## Cable contract (`:target` mode)
  #
  # Click → flips `pito.sync.<target>` between "yes" and "no" → dispatches
  # `tui:sync-changed` on document with detail
  # `{ target, parentTarget, enabled }` so the TST + sibling targets +
  # cable-suppression layer re-evaluate.
  #
  # ## i18n
  #
  # The word "sync" comes from `config/locales/tui/en.yml` `tui.tst.sync.*`.
  # All four per-state full display strings are emitted as data-* attrs.
  #
  # @contract see docs/design.md § Transitions
  class SyncIndicatorComponent < ViewComponent::Base
    include Tui::Transitionable

    MODES  = %i[tst target].freeze
    STATES = %i[idle active syncing mixed disconnected].freeze
    DEFAULT_MODE  = :tst
    DEFAULT_STATE = :idle

    def initialize(mode: DEFAULT_MODE, state: DEFAULT_STATE,
                   target: nil, parent_target: nil, focusable_key: nil)
      @mode  = MODES.include?(mode.to_sym) ? mode.to_sym : DEFAULT_MODE
      @state = STATES.include?(state.to_sym) ? state.to_sym : DEFAULT_STATE
      @target = target&.to_s
      @parent_target = parent_target&.to_s
      @focusable_key = focusable_key&.to_s

      if @mode == :target && @target.nil?
        raise ArgumentError, "Tui::SyncIndicatorComponent mode: :target requires target:"
      end
    end

    attr_reader :mode, :state, :target, :parent_target, :focusable_key

    def target_mode?
      @mode == :target
    end

    def tst_mode?
      @mode == :tst
    end

    def state_word
      case @state
      when :active, :syncing then I18n.t("tui.tst.sync.active")
      when :disconnected     then I18n.t("tui.tst.sync.disconnected", default: I18n.t("tui.tst.sync.idle"))
      when :mixed            then I18n.t("tui.tst.sync.mixed", default: I18n.t("tui.tst.sync.idle"))
      else                        I18n.t("tui.tst.sync.idle")
      end
    end

    def checkbox_glyph
      case @state
      when :active, :syncing then "[x]"
      when :disconnected     then "[!]"
      when :mixed            then "[-]"
      else                        "[ ]"
      end
    end

    def display_value
      "#{checkbox_glyph} #{state_word}"
    end

    def word_idle
      "[ ] #{I18n.t("tui.tst.sync.idle")}"
    end

    def word_active
      "[x] #{I18n.t("tui.tst.sync.active")}"
    end

    def word_syncing
      "[x] #{I18n.t("tui.tst.sync.active")}"
    end

    def word_mixed
      "[-] #{I18n.t("tui.tst.sync.mixed", default: I18n.t("tui.tst.sync.idle"))}"
    end

    def word_disconnected
      "[!] #{I18n.t("tui.tst.sync.disconnected", default: I18n.t("tui.tst.sync.idle"))}"
    end

    # Builds the merged data-attrs hash for the host span.
    def root_data_attrs
      base = transitionable_attrs(
        value: display_value,
        align: :right,
        color: color_for(@state),
        shimmer: @state == :syncing
      )
      attrs = base[:data]
      attrs[:controller] = "tui-sync-indicator #{attrs[:controller]}"
      attrs[:tui_sync_indicator_mode_value]         = @mode.to_s
      attrs[:tui_sync_indicator_idle_value]         = word_idle
      attrs[:tui_sync_indicator_active_value]       = word_active
      attrs[:tui_sync_indicator_syncing_value]      = word_syncing
      attrs[:tui_sync_indicator_mixed_value]        = word_mixed
      attrs[:tui_sync_indicator_disconnected_value] = word_disconnected
      attrs[:tui_sync_indicator_tui_transition_outlet] = ".tui-sync-word"
      attrs[:tui_status_bar_target] = "sync" if tst_mode?

      if target_mode?
        attrs[:tui_sync_indicator_target_value] = @target
        attrs[:tui_sync_indicator_parent_target_value] = @parent_target if @parent_target
        # 2026-05-24 — only `click` is wired. Native <button> already
        # converts SPACE / Enter keydown into a click event, AND the
        # `tui_cursor_controller`'s INSERT-mode SPACE handler does an
        # `el.click()` on the focused button (see
        # `toggleFocusedFocusableCheckbox`). Adding explicit
        # `keydown.space->toggle keydown.enter->toggle` actions on top of
        # those two paths caused a double-fire that toggled the sync flag
        # twice (net zero) every keystroke. The cursor controller +
        # native button activation are the single canonical paths.
        attrs[:action] = "click->tui-sync-indicator#toggle"
        if @focusable_key
          attrs[:tui_focusable] = @focusable_key
          attrs[:tui_focusable_key] = @focusable_key
          attrs[:tui_focusable_style] = "action"
        end
      end

      attrs
    end

    # Aria label for `:target` mode rendering. The controller swaps the
    # value at runtime once it knows the live state.
    def aria_label
      I18n.t("tui.sync_indicator.aria.idle", default: "sync")
    end

    private

    # Color name maps to the `kind=sync` row of the tui-transition
    # controller's COLOR_CLASS table:
    #   accent → no class (default `.tui-sync-word` color)
    #   muted  → `.is-muted` (no longer used; idle is accent per
    #             2026-05-24 "actions are always accent" lock)
    #   pink   → `.is-pink` (var(--color-danger), used for disconnected)
    def color_for(state)
      case state
      when :disconnected then :pink
      else                    :accent
      end
    end
  end
end
