module Pito
  module Calendar
    # Pito::Calendar::CategoryColors — canonical category → hex color map.
    #
    # Provides the single source of truth for the four calendar entry
    # categories (channel, game, system, manual) mapped to their display
    # colors. Consumed by:
    #
    #   - `Pito::Calendar::MonthGridComponent` — inline `background-color`
    #     on event chips (8×8 square + truncated title).
    #   - Future Rust TUI client — reads the same constants via the screen
    #     export pipeline (same-YAML / same-constant source-of-truth rule).
    #
    # Color rationale (locked 2026-05-25):
    #   channel → green  (#22c55e) — Tailwind green-500
    #   game    → blue   (#3b82f6) — Tailwind blue-500
    #   system  → amber  (#f59e0b) — Tailwind amber-500
    #   manual  → gray   (#6b7280) — Tailwind gray-500
    #
    # These do NOT use CSS variables — the chip `background-color` is an
    # inline hex because it must render correctly across the Dracula
    # dark-theme surface without needing a :root variable definition per
    # category. CSS variable wiring may be added in a later pass if the
    # TUI parity contract demands it.
    #
    # @see Pito::Calendar::MonthGridComponent
    module CategoryColors
      COLORS = {
        channel: "#22c55e",
        game:    "#3b82f6",
        system:  "#f59e0b",
        manual:  "#6b7280"
      }.freeze

      # Returns the hex color string for the given category symbol or string.
      # Falls back to the manual gray when the category is unknown.
      #
      # @param category [Symbol, String] one of :channel, :game, :system, :manual
      # @return [String] hex color, e.g. "#22c55e"
      def self.for(category)
        COLORS.fetch(category.to_sym, COLORS[:manual])
      end
    end
  end
end
