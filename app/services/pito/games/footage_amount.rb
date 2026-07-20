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
# Delta form (OWNER DIRECTIVE Q17, 3.8.0): an EXPLICITLY signed amount
# ("+2" / "-1.5") is a RELATIVE adjustment to the current total, never an
# absolute set — `delta?` detects the sign, `parse_delta` returns the signed
# half-step Rational. The magnitude rides the same ceil-to-0.5 rule `parse`
# applies ("+2.1" → +5/2, "-2.1" → -5/2), so a delta-adjusted total stays on
# the same clean half-hour grid every absolute write lands on. Flooring the
# RESULT at 0 is the CALLER's job (the handler owns the honest floored copy) —
# this stays a pure parser.
#
# Examples:
#   parse("12.5")        => (25/2)   # 12.5h
#   parse("update 12.5") => (25/2)
#   parse("2.1")         => (5/2)    # ceils UP to 2.5h
#   parse("-1")          => nil
#   parse("bogus")       => nil      # not a number
#   parse_delta("+2")    => (2/1)
#   parse_delta("-1.5")  => (-3/2)
#   parse_delta("2")     => nil      # no explicit sign — not a delta
#   parse_delta("+x")    => nil      # vague — the handler surfaces help
module Pito
  module Games
    module FootageAmount
      module_function

      # An explicit leading sign marks the amount as relative (see the module
      # comment) — the ONE token that separates a delta from an absolute set.
      DELTA_PATTERN = /\A[+-]/

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

      # @param text [String, nil] a candidate footage amount token.
      # @return [Boolean] true when the token carries an explicit +/- sign.
      def delta?(text)
        text.to_s.strip.match?(DELTA_PATTERN)
      end

      # @param text [String, nil] an explicitly signed amount ("+2" / "-1.5").
      # @return [Rational, nil] the SIGNED half-step delta, or nil when the
      #   token has no explicit sign or its magnitude isn't a clean number.
      def parse_delta(text)
        cleaned = text.to_s.strip
        return nil unless cleaned.match?(DELTA_PATTERN)

        magnitude = parse(cleaned[1..])
        return nil if magnitude.nil?

        cleaned.start_with?("-") ? -magnitude : magnitude
      end
    end
  end
end
