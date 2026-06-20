# frozen_string_literal: true

require "bigdecimal"

# Pure function. Euro-price formatter for the nullable `games.price` column.
#
# Input: a price in euros (BigDecimal / Numeric or nil). When set it is always
# > 0 (enforced by the Game validation).
# Output: "€<amount>" with exactly two decimals — "€59.99", "€8.50", "€120.00".
# Nil, zero, and negative values render as "—" so the cell stays present without
# claiming a fake €0. BigDecimal-based so there is no float drift in the parse.
module Pito
  module Formatter
    module Price
      EM_DASH = "—"

      module_function

      def call(price)
        return EM_DASH if price.nil?

        value = BigDecimal(price.to_s)
        return EM_DASH if value <= 0

        format("€%.2f", value)
      end
    end
  end
end
