# frozen_string_literal: true

require "bigdecimal"

# Pure function. Euro-price formatter for the nullable `games.price` column, and
# the single source of truth for what a price *value* means:
#   • nil          → unpriced  (unset/unknown)         → `unpriced?` → renders "—"
#   • 0 / 0.00     → free      (deliberately free)     → `free?`     → renders the star
#   • > 0          → priced    (a real amount)         → renders "€59.99" / coins
#
# Input: a price in euros (BigDecimal / Numeric or nil). Output of `.call`:
# "€<amount>" with two decimals — "€59.99", "€8.50", "€0.00". Pass `symbol: false`
# for the bare number ("59.99", "0.00") when the € is supplied elsewhere (the coin
# glyphs in Pito::Games::PriceGlyphs are the currency mark). An explicit 0 formats as
# "€0.00" — free is a real amount and gets *mentioned*, not hidden; only nil
# (unpriced) and a (forbidden) negative render "—". The free/unpriced *distinction*
# lives in `free?` / `unpriced?` so Pito::Coin + PriceGlyphs route the "0 or 0.00"
# check through here. BigDecimal-based so there is no float drift.
module Pito
  module Formatter
    module Price
      EM_DASH = "—"

      module_function

      def call(price, symbol: true)
        return EM_DASH if price.nil?

        value = BigDecimal(price.to_s)
        return EM_DASH if value.negative?

        format(symbol ? "€%.2f" : "%.2f", value)
      end

      # True when there is no price (nil = unset/unknown) — renders "—".
      def unpriced?(price)
        price.nil?
      end

      # True for an explicit 0 / 0.00 (deliberately free — the star). nil is
      # unpriced, not free; a negative (forbidden by the model) is neither.
      def free?(price)
        return false if price.nil?

        BigDecimal(price.to_s).zero?
      rescue ArgumentError, TypeError
        false
      end
    end
  end
end
