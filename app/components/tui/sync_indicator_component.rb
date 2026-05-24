module Tui
  # Tui::SyncIndicatorComponent — checkbox-style sync indicator wired through
  # the canonical `Tui::Transitionable` mixin so its value-changes pass
  # through the locked scramble-settle → color-crossfade → shimmer
  # pipeline owned by `tui_transition_controller.js`.
  #
  # 2026-05-24 (Phase 1C) — redesigned as checkbox-style display.
  # "disconnected" state dropped — cable drops are treated as idle (no
  # recent activity). Three states now drive the indicator:
  #
  #   idle   → [ ] sync  (Sidekiq quiet; muted color)
  #   active → [x] sync  (Sidekiq busy/enqueued/retry > 0; accent + shimmer)
  #   paused → [-] sync  (future per-panel pause; accent-pale color)
  #
  # The checkbox glyph ([ ] / [x] / [-]) is part of the emitted value
  # string so the Transitionable scramble effect applies to the full
  # display string, not just the word.
  #
  # Constructor inputs:
  #   - state:  one of `:idle`, `:active`, `:paused`. Defaults to `:idle`.
  #
  # Cable contract: the parent `tui-top-status-bar` controller fans
  # `pito:status_bar` payloads into `tui:sync-changed` and
  # `tui:cable-activity` events on document. This VC's child controller
  # (tui-sync-indicator) consumes both — Sidekiq activity events drive
  # :active vs :idle; the :paused state is future-wired via explicit
  # cable event. No :disconnected path exists; cable drops show as :idle.
  #
  # i18n: the word "sync" comes from `config/locales/tui/en.yml`
  # `tui.tst.sync.*`. All three per-state full display strings are also
  # emitted as data-* attrs so the JS layer can read them without
  # inlining English or reconstructing glyphs.
  #
  # @contract see docs/design.md § Transitions
  # @contract see docs/architecture.md § Pito::Transitions
  class SyncIndicatorComponent < ViewComponent::Base
    include Tui::Transitionable

    STATES = %i[idle active paused].freeze
    DEFAULT_STATE = :idle

    def initialize(state: DEFAULT_STATE)
      @state = STATES.include?(state.to_sym) ? state.to_sym : DEFAULT_STATE
    end

    attr_reader :state

    def state_word
      case @state
      when :active then I18n.t("tui.tst.sync.active")
      when :paused then I18n.t("tui.tst.sync.paused")
      else              I18n.t("tui.tst.sync.idle")
      end
    end

    def checkbox_glyph
      case @state
      when :active then "[x]"
      when :paused then "[-]"
      else              "[ ]"
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

    def word_paused
      "[-] #{I18n.t("tui.tst.sync.paused")}"
    end

    # Builds the merged data-attrs hash for the host span:
    #   - canonical tui-transition data-attrs (controller, effect, value,
    #     align, color, shimmer) from the Transitionable mixin
    #   - per-state full display strings for the colocated tui-sync-indicator
    #     controller to read in setState()
    #   - the existing top-status-bar target hook (`sync`)
    #   - the controller chain (`tui-sync-indicator tui-transition`)
    #   - the outlet selector pointing back to this same span
    def root_data_attrs
      base = transitionable_attrs(
        value: display_value,
        align: :right,
        color: color_for(@state),
        shimmer: @state == :active
      )
      attrs = base[:data]
      attrs[:controller] = "tui-sync-indicator #{attrs[:controller]}"
      attrs[:tui_sync_indicator_idle_value]   = word_idle
      attrs[:tui_sync_indicator_active_value] = word_active
      attrs[:tui_sync_indicator_paused_value] = word_paused
      attrs[:tui_sync_indicator_tui_transition_outlet] = ".tui-sync-word"
      attrs[:tui_status_bar_target] = "sync"
      attrs
    end

    private

    def color_for(state)
      case state
      when :active then :accent
      when :paused then :"accent-pale"
      else              :muted
      end
    end
  end
end
