# frozen_string_literal: true

module Pito
  module Formatter
    # Pure function. Renders an integer count as a short human-readable
    # string with K / M / B suffixes.
    #
    # Rules:
    #   nil                            → "—"
    #   0                              → "0"
    #   1..999                         → "<n>"
    #   1_000..9_999                   → 1-decimal K, drop trailing ".0"
    #   10_000..999_999                → integer K
    #   1_000_000..9_999_999           → 1-decimal M, drop trailing ".0"
    #   10_000_000..999_999_999        → integer M
    #   1_000_000_000..9_999_999_999   → 1-decimal B, drop trailing ".0"
    #   10_000_000_000+                → integer B
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

      def format_tier(n, unit, suffix)
        scaled = n.to_f / unit

        if scaled < 10
          rounded = (scaled * 10).round / 10.0
          if rounded >= 10
            return "10#{suffix}"
          end
          if (rounded * 10).round % 10 == 0
            "#{rounded.to_i}#{suffix}"
          else
            "#{rounded}#{suffix}"
          end
        else
          rounded = scaled.round
          if rounded >= 1_000 && suffix != "B"
            call(rounded * unit)
          else
            "#{rounded}#{suffix}"
          end
        end
      end
    end
  end
end
