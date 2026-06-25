# frozen_string_literal: true

require "bigdecimal"

module Pito
  # Price → coin tier. Pure domain logic: how *expensive* a game reads at a
  # glance — 1 coin (budget) to 5 (premium/collector) — with two non-coin states:
  #   • `:unpriced` — nil price (unset/unknown). Renders as "—", NOT a glyph.
  #   • `:free`     — an explicit 0 / 0.0 ("genuine value"). Renders as the star.
  # The two are distinct on purpose: most games carry no price yet (→ "—"); only a
  # game *deliberately* marked 0 reads as free. Thresholds are .99 boundaries so
  # real prices split cleanly (old AAA €59.99 → 3, new-AAA €69.99–79.99 → 4, €80+
  # deluxe/collector → 5) and stay robust to round prices (€60.00 → 4, €45.00 → 3).
  #
  # This module owns only the *tier* — no rendering, no number formatting.
  # The number is Pito::Formatter::Price; the glyphs are Pito::Game::PriceGlyphs.
  module Coin
    # [inclusive upper bound (EUR), coin count] for tiers 1..4, in ascending
    # order. A price above the last threshold is MAX_TIER. nil → :unpriced and
    # 0 → :free are decided before these apply.
    TIERS = [
      [ BigDecimal("9.99"),  1 ], # budget / sale
      [ BigDecimal("29.99"), 2 ], # indie / value
      [ BigDecimal("59.99"), 3 ], # AA / classic AAA
      [ BigDecimal("79.99"), 4 ]  # new-AAA full price
    ].freeze

    MAX_TIER = 5         # premium / collector (> 79.99)
    FREE     = :free     # explicit 0 — the star
    UNPRICED = :unpriced # nil — the em-dash

    module_function

    # The tier: `:unpriced` for nil, `:free` for an explicit 0, else 1..5.
    # The nil / "0 or 0.00" classification is owned by Pito::Formatter::Price;
    # Coin only adds the tier thresholds for a positive amount. A negative
    # (forbidden by the model) falls through to :unpriced.
    def tier(price)
      return UNPRICED if Pito::Formatter::Price.unpriced?(price)
      return FREE     if Pito::Formatter::Price.free?(price)

      value = BigDecimal(price.to_s)
      return UNPRICED if value.negative?

      TIERS.each { |threshold, count| return count if value <= threshold }
      MAX_TIER
    end

    # True only for an explicit 0 (the star). nil is :unpriced, not free.
    def free?(price)
      Pito::Formatter::Price.free?(price)
    end

    # True when there is no price to show (nil) — renders "—", no glyph.
    def unpriced?(price)
      Pito::Formatter::Price.unpriced?(price)
    end

    # How many coin glyphs to draw: 0 when free/unpriced, else the tier (1..5).
    def coin_count(price)
      t = tier(price)
      t.is_a?(Integer) ? t : 0
    end
  end
end
