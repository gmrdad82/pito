# frozen_string_literal: true

require "bigdecimal"

# Pure function. Parses the `footage [update] <hours>` amount typed for the
# `games.footage_hours` column — the single canonical parser the `footage` chat
# tool, its game-detail follow-up reply, and the `:footage_hours` dispatch
# resolver all share — "wrap, don't fork".
#
# Contract:
#   * Tolerates an optional leading `update` token (`update 12.5` == `12.5`).
#   * BigDecimal keeps the value exact (no float drift), then ceils UP to the
#     next clean half-hour (1800 s = 0.5 h) via integer math, returning an exact
#     Rational on a 0.5 step.
#   * Non-numeric / negative input → nil (the handlers surface a usage hint).
#
# Examples:
#   parse("12.5")        => (25/2)   # 12.5h
#   parse("update 12.5") => (25/2)
#   parse("2.1")         => (5/2)    # ceils UP to 2.5h
#   parse("-1")          => nil
#   parse("bogus")       => nil      # not a number
module Pito
  module Games
    module FootageAmount
      module_function

      # @param text [String, nil] the footage amount phrase (optionally `update`-prefixed).
      # @return [Rational, nil] exact half-step hours, or nil for non-numeric/negative.
      def parse(text)
        cleaned = text.to_s.strip.sub(/\Aupdate\b\s*/i, "").strip
        value   = BigDecimal(cleaned)
        return nil if value.negative?

        (value * 2).ceil / 2r # BigDecimal#ceil → Integer; exact Rational on a 0.5 step
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
