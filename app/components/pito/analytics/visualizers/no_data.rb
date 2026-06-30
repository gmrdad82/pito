# frozen_string_literal: true

module Pito
  module Analytics
    module Visualizers
      # Placeholder widget shown when a metric has NO data to plot (e.g. YouTube
      # withholds geography/demographics for a scope/period). For now it is a BLANK
      # canvas — the same `.pito-metric` chrome + dotted-paper background grid the
      # area chart / heart wear (Base), filled with blank braille rows so
      # the canvas keeps its dimensions and the graph-paper grid shows through.
      #
      # The actual content (whatever sits on the blank canvas) is intentionally
      # deferred — the owner will specify it; this is the skeleton it hangs on.
      #
      # Mirrors the Pito::Analytics::Visualizers::Heart canvas approach: one `white-space: pre`
      # block per row, sized by `--pito-rows`, with `background_layer(baseline:)`
      # behind it.
      #
      # `size: :compact` shrinks the canvas to the 2-row sparkline height (same as
      # `Pito::Analytics::Visualizers::Sparkline::ROWS`) so a no-data placeholder can
      # sit in a compact glance slot at the correct height. `size: :regular` (default)
      # keeps the full 11-row Base canvas used by area / heart / bar charts.
      #
      # Rows carry the SAME diagonal pito-blue shimmer as the area chart rows
      # (`.pito-metric__row` + `.pito-shimmer-dN` stagger) so the dotted canvas
      # pulses at 135° even when empty.
      class NoData < Pito::Analytics::Visualizers::Base
        BLANK = [ 0x2800 ].pack("U")

        # @param caption [String] optional pre-rendered html-safe caption (blank for now)
        # @param size    [:regular, :compact] canvas height — :regular = full 11-row Base
        #                canvas (same as area/heart/bar); :compact = 2-row sparkline height.
        def initialize(caption: "", size: :regular)
          super(caption:)
          @size = size
        end

        # Per-instance row count: compact shrinks to the sparkline canvas (2 rows);
        # regular keeps the full Base canvas (11 rows).
        def rows          = @size == :compact ? Pito::Analytics::Visualizers::Sparkline::ROWS : self.class::ROWS
        def bg_rows_count = @size == :compact ? Pito::Analytics::Visualizers::Sparkline::ROWS : self.class::ROWS

        # A full-width row of VISIBLE faint dots (last row = baseline floor). The
        # dots carry ink so the `.pito-metric--nodata` shimmer (faded base + the area
        # chart's 135° pito-blue sweep) has glyphs to clip to — a blank braille row
        # would be inkless and the shimmer would never show.
        def dot_row(i) = ((i == rows - 1) ? BASELINE_DOT : BG_DOT) * cols

        # Staggered shimmer-delay bucket — same mechanism as area chart rows —
        # seeded per caption so different no-data placeholders never pulse in sync.
        def shimmer_offset_class
          Pito::Shimmer.offset_class(caption.presence || "no-data-canvas")
        end
      end
    end
  end
end
