# frozen_string_literal: true

module Pito
  module Analytics
    module Visualizers
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
      # Abstract: not rendered directly — subclass it (e.g. AreaChart) with a
      # template that draws the plot inside this chrome.
      class Base < ViewComponent::Base
        # Braille CELL grid: COLS ≈ a vid thumbnail width; ROWS ≈ a 16:9 box at the
        # 14px base line-height. COLS trimmed to 45 (owner 2026-06-28) so the chart
        # never overruns a narrow/portrait column. (The likes hearts are a SEPARATE
        # locked width — Pito::Analytics::Visualizers::Heart::HEART_COLS — not derived from this.)
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

        # Single braille dot for the chart BACKGROUND grid — an evenly-spaced
        # dotted-paper look (a 2×2 block bands edge-to-edge between cells, so one
        # dot reads cleaner). Rendered BEHIND the data rows in a TRANSLUCENT fg
        # tint (see .pito-metric__bg) so it lifts WHATEVER background sits behind
        # it — the page (--bg-root) or a surfaced message (--bg-surface) — and a
        # chart's empty cells show it instead of blank.
        BG_DOT = [ 0x2802 ].pack("U") # ⠂ — one dot
        # Bottom-row floor dot (dots 7,8) — matches the area chart's baseline so a
        # renderer with no data floor (the heart) can sit on the same baseline.
        BASELINE_DOT = [ 0x28C0 ].pack("U") # ⣀

        # Background-grid CELL dims. Default to the chart box; a renderer whose
        # canvas differs OVERRIDES these (e.g. the heart uses fewer rows).
        def bg_cols       = cols
        def bg_rows_count = rows

        # The shared faint dotted background LAYER (graph-paper) every metric
        # renderer wears — a dim braille dot per cell, behind the data rows (whose
        # blank cells let it show through). CENTRALISED here so EVERY current and
        # future chart/renderer gets it just by calling `<%= background_layer %>`
        # in its template. html_safe. `baseline: true` makes the LAST row a floor
        # line (⣀) so a floorless renderer (the heart) aligns to the area chart.
        def background_layer(baseline: false)
          n = bg_rows_count
          rows_html = safe_join(
            Array.new(n) { |i| tag.span(((baseline && i == n - 1) ? BASELINE_DOT : BG_DOT) * bg_cols, class: "pito-metric__bg-row") }
          )
          tag.div(rows_html, class: "pito-metric__bg", "aria-hidden": "true")
        end
      end
    end
  end
end
