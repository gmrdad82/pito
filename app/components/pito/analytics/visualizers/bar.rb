# frozen_string_literal: true

module Pito
  module Analytics
    module Visualizers
      # Horizontal bar-GROUP chart: 1–5 bars rendered as braille ⣿ glyph rows,
      # vertically centred on the SAME COLS×ROWS canvas as the area chart / heart
      # (Base). Each bar is 2 rows tall (identical glyph rows), with a
      # 1-row gap between bars for n≤4 (no gap at n=5 — 10 bar rows + 1 pad = 11).
      # Wears the same pito-blue shimmer + bottom→up reveal as the area chart.
      #
      # Inputs:
      #   bars:    Array of 1..5 Hashes:
      #              { label: String, pct: Numeric(0..100), color: Symbol,
      #                value_label: String (optional, defaults to "XX.X%") }
      #   caption: pre-rendered html-safe caption (passed through to Base)
      #
      # Colour tokens mirror the full accent palette (no --accent-pink exists in the
      # palette; pink is synthesised as an oklch mix of red + purple, matching the
      # TimeToBeat "insanity" convention in application.css line ~1347).
      class Bar < Pito::Analytics::Visualizers::Base
        REVEAL_CONTROLLER = "pito--area-chart-reveal"

        BLANK    = [ 0x2800 ].pack("U") # ⠀ braille blank — bg grid shows through
        BAR_FILL = [ 0x28FF ].pack("U") # ⣿ full 8-dot braille block

        COLOR_TOKENS = {
          red:    "var(--accent-red)",
          green:  "var(--accent-green)",
          blue:   "var(--brand-pito)",
          purple: "var(--accent-purple)",
          cyan:   "var(--accent-cyan)",
          pink:   "color-mix(in oklch, var(--accent-red) 50%, var(--accent-purple))",
          yellow: "var(--accent-yellow)",
          orange: "var(--accent-orange)"
        }.freeze

        # @param bars    [Array<Hash>] 1..5 bar descriptors (see class docs)
        # @param caption [String] pre-rendered html-safe caption (Base)
        def initialize(bars:, caption:)
          super(caption:)
          @bars = Array(bars).first(5).map do |b|
            pct = b[:pct].to_f.clamp(0.0, 100.0)
            {
              label:       b[:label].to_s,
              pct:         pct,
              color:       b[:color],
              value_label: b.key?(:value_label) ? b[:value_label].to_s : format("%.1f%%", pct)
            }
          end
        end

        def reveal_controller = REVEAL_CONTROLLER

        # Staggered shimmer-delay bucket — seeded per bar-set so adjacent charts
        # never pulse in sync (mirrors Pito::Analytics::Visualizers::Heart#shimmer_offset_class).
        def shimmer_offset_class
          seed = @bars.map { |b| "#{b[:color]}#{b[:pct]}" }.join(",")
          Pito::Shimmer.offset_class(seed)
        end

        # The 11 plot rows (top→bottom) ready for the template. Each entry is
        # either :blank (pad / gap row) or a bar-data hash pre-computed for one
        # bar row. The template renders each at absolute index i (0..10) so the
        # shimmer band offset is continuous across the full canvas.
        def plot_rows
          @plot_rows ||= build_plot_rows
        end

        # Per-bar legend data for the legend block.
        def legend_bars
          bars_data
        end

        private

        # How many filled cells for a given percentage.
        # Tiny positive pct shows ≥1 cell; 0% shows nothing.
        def filled_cells(pct)
          return 0 unless pct.positive?
          [ (pct / 100.0 * COLS).round, 1 ].max.clamp(0, COLS)
        end

        # Offset (in cells) for a cumulative percentage — where a bar's coloured
        # segment STARTS.
        def offset_cells(pct)
          ((pct / 100.0) * COLS).round.clamp(0, COLS)
        end

        def color_token(sym)
          COLOR_TOKENS.fetch(sym&.to_sym, COLOR_TOKENS[:blue])
        end

        # Pre-computed bar rows (memoised). Each bar's coloured segment STARTS at
        # the running cumulative offset (where the previous bar's slice ended) — so
        # the slices tile the 0–100% line down the stack (owner: the subscribed
        # segment begins where not-subscribed ends, "........⣿"). Each row = a dim
        # lead (offset cells), the coloured segment (filled), then a dim tail.
        def bars_data
          @bars_data ||= begin
            running = 0.0
            @bars.map do |b|
              want = filled_cells(b[:pct])
              # Place the segment at the cumulative offset, but never let a positive
              # slice get pushed off-canvas — keep its `want` cells visible (so a tiny
              # last slice like subscribed 0.8% still shows as "........⣿").
              off  = [ offset_cells(running), COLS - want ].min
              running += b[:pct]
              {
                label:       b[:label],
                value_label: b[:value_label],
                token:       color_token(b[:color]),
                offset:      off,
                filled:      want,
                remainder:   COLS - off - want
              }
            end
          end
        end

        def build_plot_rows
          n        = @bars.size
          # gap_rows = 1 when 2n + (n-1) ≤ ROWS; the boundary is n=4 (11 ≤ 11).
          gap      = (2 * n + (n - 1) <= ROWS) ? 1 : 0
          content  = 2 * n + gap * (n - 1)
          top_pad  = (ROWS - content) / 2

          result = []
          top_pad.times { result << :blank }

          bars_data.each_with_index do |bd, j|
            result << :blank if j.positive? && gap > 0
            result << bd     # row 1 of bar (same glyph row ×2)
            result << bd     # row 2 of bar
          end

          (ROWS - result.size).times { result << :blank }
          result
        end
      end
    end
  end
end
