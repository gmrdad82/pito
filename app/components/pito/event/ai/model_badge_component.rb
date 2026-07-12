# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # The ✨ model indicator pinned to an :ai message's bottom-right corner —
      # an inline Lucide `sparkles` glyph (ISC, no external fetch; stroked with
      # the AI thread's purple→pito-blue gradient, same as the accent bar) next
      # to the answering model's name and, when the model's catalog exposes
      # pricing, what THIS answer cost — the house coin followed by a
      # two-decimal amount and its currency code. Absolutely positioned chrome:
      # it marks WHO wrote the answer and what it cost without taking part in
      # the block flow. Renders nothing for messages that predate the payload's
      # `model` stamp; the cost renders only when stamped.
      class ModelBadgeComponent < ViewComponent::Base
        COIN_SRC = Pito::Games::PriceGlyphs::COIN_SRC

        def initialize(model:, cost_amount: nil, cost_currency: nil)
          @model         = model.to_s
          @cost_amount   = cost_amount
          @cost_currency = cost_currency.to_s
        end

        attr_reader :model

        def render?
          model.present?
        end

        # Symbol currencies ATTACH to the amount (typographically correct:
        # "$0.00", no space); currencies without a symbol fall back to
        # "0.00 XXX" — ISO codes take the space.
        CURRENCY_SYMBOLS = { "USD" => "$", "EUR" => "€", "GBP" => "£" }.freeze

        def cost?
          !@cost_amount.nil?
        end

        # "$0.01" / "0.01 CHF" — two decimals per the owner's spec; the coin
        # glyph is pito's mark, the symbol/code names the currency.
        def cost_text
          amount = format("%.2f", @cost_amount.to_f)
          symbol = CURRENCY_SYMBOLS[currency_code]
          symbol ? "#{symbol}#{amount}" : "#{amount} #{currency_code}"
        end

        def currency_code
          (@cost_currency.presence || "USD").upcase
        end
      end
    end
  end
end
