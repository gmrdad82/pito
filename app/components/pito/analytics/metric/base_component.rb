# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # Shared base / engine for a bespoke analytics metric widget. Owns the common
      # chrome every metric chart wears — the braille canvas dimensions (COLS×ROWS)
      # and the pre-rendered caption line — so each concrete metric component only
      # supplies its OWN viz (the plot) and any metric-specific reveal animation (a
      # JS controller that `extends` the base reveal engine).
      #
      # There are NO axis lines/names (locked spec): the braille baseline dot-floor
      # IS the x baseline, and discrete tick VALUES (y inside-left, x below) carry
      # the scale — those live on the concrete component (it owns the data).
      #
      # Abstract: not rendered directly — subclass it (e.g. ViewsComponent) with a
      # template that draws the plot inside this chrome.
      class BaseComponent < ViewComponent::Base
        # Braille CELL grid: COLS ≈ a vid thumbnail width (+2ch); ROWS ≈ a 16:9 box
        # at the 14px base line-height.
        COLS = 45
        ROWS = 11

        # @param caption [String] pre-rendered, html-safe caption (the builder
        #   samples a no-repeat variant per message and passes it in)
        def initialize(caption:)
          @caption = caption
        end

        attr_reader :caption

        def cols = self.class::COLS
        def rows = self.class::ROWS
      end
    end
  end
end
