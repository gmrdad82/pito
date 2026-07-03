# frozen_string_literal: true

require "bigdecimal"

# Pure function. Parses the `price [set] <amount>` euro value for the nullable
# `games.price` column — the single canonical parser the `price` chat verb, its
# game-detail follow-up reply, and the `:price_amount` dispatch resolver all
# share (plan-0.9.5 T8.15 — "wrap, don't fork").
#
# Contract:
#   * BigDecimal keeps the value exact, rounded to 2 decimals.
#   * Must be non-negative — an explicit 0 is a valid price (free, the star).
#   * Blank / non-numeric / negative input → nil (the handlers surface a hint).
#
# Examples:
#   parse("9.99")  => 0.999e1
#   parse("0")     => 0.0        # free
#   parse("-1")    => nil
#   parse("")      => nil
#   parse("free")  => nil
module Pito
  module Games
    module PriceAmount
      module_function

      # @param raw [String, nil] the euro amount token.
      # @return [BigDecimal, nil] non-negative amount (2dp), or nil for blank/non-numeric/negative.
      def parse(raw)
        return nil if raw.blank?

        value = BigDecimal(raw.to_s).round(2)
        return nil if value.negative?

        value
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
