module Tui
  # Tui::SyncIndicatorComponent — 3-state visual sync indicator pinned to TST.
  #
  # States (set by Stimulus controller via data-tui-sync-indicator-state-value):
  #   - "synced"       muted  "[ ] sync"  — cable idle, no animation
  #   - "syncing"      accent "[x] sync"  — cable activity, shimmer animation
  #   - "disconnected" danger "[ ] sync"  — cable lost, no animation (color-only)
  #
  # Default initial state: "synced". The Stimulus controller flips to
  # "syncing" on any `pito:cable-activity` event (debounced 300 ms back to
  # "synced") and to "disconnected" on `pito:cable:disconnected`.
  #
  # Single instance: TST master only. No click handler. No target mode.
  # No per-panel mounting.
  #
  # Kwargs:
  #   initial_state [String] One of "synced", "syncing", "disconnected".
  #                           Defaults to "synced".
  #
  # Cable events consumed (JS side):
  #   pito:cable-activity   — transitions to "syncing", resets after 300 ms
  #   pito:cable:disconnected — transitions to "disconnected"
  #   pito:cable:connected  — if currently "disconnected", transitions to "synced"
  #
  # Related:
  #   app/javascript/controllers/tui_sync_indicator_controller.js
  #   app/assets/tailwind/application.css  (§ tui-sync-indicator)
  class SyncIndicatorComponent < ViewComponent::Base
    STATES = %w[synced syncing disconnected].freeze
    DEFAULT_STATE = "synced".freeze

    def initialize(initial_state: DEFAULT_STATE)
      @initial_state = STATES.include?(initial_state.to_s) ? initial_state.to_s : DEFAULT_STATE
    end

    attr_reader :initial_state

    # Returns the bracket glyph character for a given state string.
    # Only "syncing" gets a non-blank glyph. "disconnected" uses the same
    # blank glyph as "synced" — distinguished by color (danger red) instead.
    def glyph_for(state)
      state == "syncing" ? "x" : " "
    end
  end
end
