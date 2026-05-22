module Tui
  # Tui::SyncIndicatorComponent — word-only sync indicator wired through
  # the canonical `Tui::Transitionable` mixin so its value-changes pass
  # through the locked scramble-settle → color-crossfade → shimmer
  # pipeline owned by `tui_transition_controller.js` (Wave 1B).
  #
  # 2026-05-22 (Phase 2A) — glyphs (●/◐/✗) dropped per Beta 4 word-only
  # contract. State now drives only the word ("synced" / "syncing" /
  # "disconnected"), the active color (accent for synced/syncing,
  # pink/danger for disconnected), and the shimmer decoration (syncing
  # only). The colocated `tui-sync-indicator` controller is a thin
  # delegator that listens for `tui:sync-changed` + `tui:cable-activity`
  # events and patches the colocated `tui-transition` outlet via
  # setValue / setColor / setShimmer. Sequencing rule: shimmer NEVER
  # overlaps the scramble (forward path waits for
  # `tui-transition:settled` before flipping shimmer on; reverse path
  # turns shimmer off first, then scrambles back).
  #
  # Constructor inputs:
  #   - state:  one of `:synced`, `:syncing`, `:disconnected`. Accepts
  #             `:idle` as a soft alias to `:synced` to preserve the
  #             existing wire format from `StatusBarBroadcastJob`
  #             (`sync_state: :idle`). Defaults to `:synced`.
  #
  # Cable contract: the parent `tui-top-status-bar` controller fans
  # `pito:status_bar` payloads into `tui:sync-changed` and
  # `tui:cable-activity` events on document. This VC's child controller
  # consumes both — explicit state events drive `disconnected`, activity
  # events drive a 400ms `syncing` pulse, quiescence returns the cell to
  # `synced`.
  #
  # i18n: words come from `config/locales/tui/en.yml` `tui.tst.sync.*`.
  # All three per-state words are also emitted as data-* attrs so the
  # JS layer can read them without inlining English.
  #
  # @contract see docs/design.md § Transitions
  # @contract see docs/architecture.md § Pito::Transitions
  class SyncIndicatorComponent < ViewComponent::Base
    include Tui::Transitionable

    STATES = %i[synced syncing disconnected].freeze
    DEFAULT_STATE = :synced

    def initialize(state: DEFAULT_STATE)
      @state = normalize_state(state)
    end

    attr_reader :state

    def state_word
      case @state
      when :synced       then I18n.t("tui.tst.sync.synced")
      when :syncing      then I18n.t("tui.tst.sync.syncing")
      when :disconnected then I18n.t("tui.tst.sync.disconnected")
      end
    end

    def word_synced
      I18n.t("tui.tst.sync.synced")
    end

    def word_syncing
      I18n.t("tui.tst.sync.syncing")
    end

    def word_disconnected
      I18n.t("tui.tst.sync.disconnected")
    end

    # Builds the merged data-attrs hash for the host span:
    #   - canonical tui-transition data-attrs (controller, effect, value,
    #     align, color, shimmer) from the Transitionable mixin
    #   - per-state word values for the colocated tui-sync-indicator
    #     controller to read in setState()
    #   - the existing top-status-bar target hook (`sync`)
    #   - the controller chain (`tui-sync-indicator tui-transition`)
    #   - the outlet selector pointing back to this same span
    def root_data_attrs
      base = transitionable_attrs(
        value: state_word,
        align: :right,
        color: color_for(@state),
        shimmer: @state == :syncing
      )
      attrs = base[:data]
      attrs[:controller] = "tui-sync-indicator #{attrs[:controller]}"
      attrs[:tui_sync_indicator_synced_value]       = word_synced
      attrs[:tui_sync_indicator_syncing_value]      = word_syncing
      attrs[:tui_sync_indicator_disconnected_value] = word_disconnected
      attrs[:tui_sync_indicator_tui_transition_outlet] = ".tui-sync-word"
      attrs[:tui_status_bar_target] = "sync"
      attrs
    end

    private

    def normalize_state(raw)
      sym = raw.to_sym
      sym = :synced if sym == :idle
      STATES.include?(sym) ? sym : DEFAULT_STATE
    end

    def color_for(state)
      case state
      when :syncing      then :accent
      when :disconnected then :danger
      else                    :muted
      end
    end
  end
end
