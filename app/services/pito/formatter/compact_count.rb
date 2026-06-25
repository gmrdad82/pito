# frozen_string_literal: true

module Pito
  module Formatter
    # Pure function. Renders an integer count as a short human-readable
    # string with K / M / B suffixes.
    #
    # ROUNDS DOWN (floor / truncate), never up — the displayed compact value must
    # never OVERSTATE the real number, so the true count is always ≥ what's shown
    # (a pleasant surprise: `2,259` reads as `2.2K`, not `2.3K`). Owner rule.
    #
    # Rules (all truncated toward zero):
    #   nil                            → "—"
    #   0                              → "0"
    #   1..999                         → "<n>"
    #   1_000..9_999                   → 1-decimal K floored, drop trailing ".0"
    #   10_000..999_999                → integer K floored
    #   1_000_000..9_999_999           → 1-decimal M floored, drop trailing ".0"
    #   10_000_000..999_999_999        → integer M floored
    #   1_000_000_000..9_999_999_999   → 1-decimal B floored, drop trailing ".0"
    #   10_000_000_000+                → integer B floored
    module CompactCount
      EM_DASH = "—"

      module_function

      def call(value)
        return EM_DASH if value.nil?

        n = value.to_i
        return "0" if n.zero?

        if n < 1_000
          n.to_s
        elsif n < 1_000_000
          format_tier(n, 1_000, "K")
        elsif n < 1_000_000_000
          format_tier(n, 1_000_000, "M")
        else
          format_tier(n, 1_000_000_000, "B")
        end
      end

      # Always floored so the display never overstates the real count.
      def format_tier(n, unit, suffix)
        scaled = n.to_f / unit

        if scaled < 10
          tenths = (scaled * 10).floor # 0..99 (one decimal, floored)
          whole  = tenths / 10
          frac   = tenths % 10
          frac.zero? ? "#{whole}#{suffix}" : "#{whole}.#{frac}#{suffix}"
        else
          "#{scaled.floor}#{suffix}" # integer, floored
        end
      end
    end
  end
end
