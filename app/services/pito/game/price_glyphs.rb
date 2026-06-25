# frozen_string_literal: true

module Pito
  module Game
    # Renders a game price as inline coin glyphs + the number — or, for the two
    # non-coin states, a star (free) or an em-dash (unpriced). Returns an html_safe
    # String for a table cell (`html: true`) or a KeyValueRow value. Composes the
    # domain pieces — Pito::Coin (the tier) and Pito::Formatter::Price (the number,
    # `symbol: false`, since the coins ARE the currency mark). Mirrors
    # PlatformTokens.icons_html.
    #
    #   PriceGlyphs.html(59.99) # => "🪙🪙🪙&nbsp;59.99"  (3 coins + the number)
    #   PriceGlyphs.html(0)     # => "⭐&nbsp;0.00"       (the FREE star + the number)
    #   PriceGlyphs.html(nil)   # => "—"                 (unpriced — no glyph, no number)
    module PriceGlyphs
      COIN_SRC = "/coin/coin.gif"
      STAR_SRC = "/coin/star.gif"

      module_function

      # html_safe String. nil → "—"; else a glyph run + the number: the FREE star +
      # "0.00" for an explicit 0, or N coins + "59.99" for a real price. Free reads
      # like the coins do (glyph + number) so the 0.00 is always shown.
      def html(price)
        return em_dash if Pito::Coin.unpriced?(price)

        number = ERB::Util.html_escape(Pito::Formatter::Price.call(price, symbol: false))
        glyphs = Pito::Coin.free?(price) ? star_img : coin_imgs(Pito::Coin.coin_count(price))
        # No &nbsp; — the small coins↔number gap is CSS (.pito-coins margin) so it
        # stays tight; the glyph run is raised onto the digit baseline there too.
        %(<span class="pito-coins">#{glyphs}</span>#{number}).html_safe
      end

      # The unpriced em-dash (matches Formatter::Price's nil rendering).
      def em_dash
        ERB::Util.html_escape(Pito::Formatter::Price.call(nil)).html_safe
      end

      # `count` coin <img> tags (decorative — alt empty, hidden from a11y; the
      # number carries the meaning).
      def coin_imgs(count)
        img = %(<img class="pito-coin" src="#{COIN_SRC}" alt="" aria-hidden="true" loading="lazy">)
        img * count
      end

      # The FREE star <img> — labelled for a11y; the "0.00" beside it carries the value.
      def star_img
        %(<img class="pito-coin pito-coin--free" src="#{STAR_SRC}" alt="Free" title="Free" loading="lazy">)
      end
    end
  end
end
