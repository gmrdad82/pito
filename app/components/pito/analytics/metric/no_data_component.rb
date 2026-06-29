# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # Placeholder widget shown when a metric has NO data to plot (e.g. YouTube
      # withholds geography/demographics for a scope/period). For now it is a BLANK
      # canvas — the same `.pito-metric` chrome + dotted-paper background grid the
      # area chart / heart wear (BaseComponent), filled with blank braille rows so
      # the canvas keeps its dimensions and the graph-paper grid shows through.
      #
      # The actual content (whatever sits on the blank canvas) is intentionally
      # deferred — the owner will specify it; this is the skeleton it hangs on.
      #
      # Mirrors the HeartChartComponent canvas approach: one `white-space: pre`
      # block per row, sized by `--pito-rows`, with `background_layer(baseline:)`
      # behind it.
      class NoDataComponent < BaseComponent
        BLANK = [ 0x2800 ].pack("U")

        # @param caption [String] optional pre-rendered html-safe caption (blank for now)
        def initialize(caption: "")
          super(caption:)
        end

        # A full-width row of blank braille cells (the bg grid shows through).
        def blank_row = BLANK * cols
      end
    end
  end
end
