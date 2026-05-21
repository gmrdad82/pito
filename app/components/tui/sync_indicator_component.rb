module Tui
  # Beta 4 — extracted from `Tui::TopStatusBarComponent` (2026-05-21)
  # per "ViewComponents are kings" — sub-elements of the top status
  # bar each get their own VC + spec.
  #
  # Sync indicator: ●/✗ glyph + word ("synced" / "syncing" /
  # "disconnected") + optional target label rendered immediately
  # after the word for `:syncing_with_target`.
  #
  # Visual rules + class hooks mirror the locked demo at
  # `tmp/demo-status-bar-final.html` and Lane C's
  # `tui_status_bar_controller.js` which patches the same DOM cells.
  #
  # Constructor inputs:
  #   - state:  one of `:idle`, `:syncing`, `:syncing_with_target`,
  #             `:disconnected`. Drives the dot glyph + dot color +
  #             word + word color. Defaults to `:idle`.
  #   - target: optional string. Rendered after the word for
  #             `:syncing_with_target` (e.g. "syncing channels"
  #             → target="channels"). Ignored for other states.
  #
  # The root element + each child carry the
  # `data-tui-status-bar-target="..."` attributes that the cable
  # Stimulus controller subscribes to — this VC is a drop-in render
  # inside `Tui::TopStatusBarComponent` and does not break the live
  # update contract.
  class SyncIndicatorComponent < ViewComponent::Base
    STATES = %i[idle syncing syncing_with_target disconnected].freeze

    def initialize(state: :idle, target: nil)
      @state = STATES.include?(state.to_sym) ? state.to_sym : :idle
      @target = target.presence
    end

    attr_reader :state, :target

    def dot_glyph
      @state == :disconnected ? "✗" : "●"
    end

    def dot_class
      case @state
      when :idle              then "sb-sync-dot sb-sync-dot--green"
      when :syncing, :syncing_with_target then "sb-sync-dot sb-sync-dot--amber"
      when :disconnected      then "sb-sync-dot sb-sync-dot--red"
      end
    end

    def word
      case @state
      when :idle              then "synced"
      when :syncing, :syncing_with_target then "syncing"
      when :disconnected      then "disconnected"
      end
    end

    def word_class
      case @state
      when :idle              then "sb-sync-word sb-sync-word--idle"
      when :syncing, :syncing_with_target then "sb-sync-word sb-sync-word--syncing"
      when :disconnected      then "sb-sync-word sb-sync-word--disconnected"
      end
    end

    def target_visible?
      @state == :syncing_with_target && @target.present?
    end
  end
end
