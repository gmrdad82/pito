# Phase 37 Wave A1 — `Pito::Formatter::CompactCount`.
#
# Pure function. Renders an integer count as a short human-readable
# string with K / M / B suffixes. Designed for the
# `Channel::IdCardComponent` metric rows (subscribers, views) where the
# card cell is too narrow for the full integer.
#
# Rules (locked 2026-05-19, user):
#
#   nil                            → "—" (em-dash)
#   0                              → "0"
#   1..999                         → "<n>"           (e.g. "3", "47", "589")
#   1_000..9_999                   → 1-decimal K, drop trailing ".0"
#                                    (e.g. 1_000 → "1K", 1_500 → "1.5K",
#                                     2_300 → "2.3K")
#   10_000..999_999                → integer K
#                                    (e.g. 10_000 → "10K", 47_500 → "48K",
#                                     999_999 → rolls up into M tier)
#   1_000_000..9_999_999           → 1-decimal M, drop trailing ".0"
#                                    (e.g. 1_000_000 → "1M", 2_300_000 → "2.3M")
#   10_000_000..999_999_999        → integer M (e.g. 47_000_000 → "47M")
#   1_000_000_000..9_999_999_999   → 1-decimal B, drop trailing ".0"
#   10_000_000_000+                → integer B
#
# Suffixes are ALWAYS uppercase (K / M / B). Rounding is round-half-up at
# the rendered precision; when the rounded value rolls up across a tier
# boundary (e.g. 9_999 rounded at one decimal place → 10.0K → switch to
# integer-K rendering), we re-enter the next tier's branch so the output
# stays consistent. Pure function — no I/O, no I18n, no Rails dependency.
module Pito
  module Formatter
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

      # Render `n` in the tier with `unit` divisor and `suffix`.
      #
      # Below 10× the unit we render at one decimal place dropping a
      # trailing ".0"; at or above 10× we render as an integer. If the
      # one-decimal-place rounding rolls the value up to the next tier
      # (e.g. 999_999 → 1_000K → recurse into M), we recurse so the output
      # follows the tier the rounded value lands in, not the tier the raw
      # input started in.
      def format_tier(n, unit, suffix)
        scaled = n.to_f / unit

        if scaled < 10
          rounded = (scaled * 10).round / 10.0
          if rounded >= 10
            # Tier roll-up at boundary (e.g. 9_950..9_999 → 10K).
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
            # Roll into next tier (e.g. 999_999 → 1M, 999_999_999 → 1B).
            call(rounded * unit)
          else
            "#{rounded}#{suffix}"
          end
        end
      end
    end
  end
end
