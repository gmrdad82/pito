# frozen_string_literal: true

module Pito
  module Analytics
    module Metric
      # Bespoke widget for the `likes` `:system` metric — the braille-HEART analogue
      # of AreaChartComponent. Renders one or two hearts side by side (subject +
      # channel, or channel alone), each FILLED bottom→top to a 0..100 "likes vs
      # dislikes" score, with a likes/dislikes legend under each and a witty caption
      # below.
      #
      # CONTAINER UNITY (locked): this reuses the SAME `.pito-metric` /
      # `.pito-metric__chart` / `.pito-metric__plot` / `.pito-metric__caption`
      # chrome the area charts wear (BaseComponent) — so portrait/landscape flow,
      # max-width clamping and the bottom→up reveal come for FREE. The ONLY
      # heart-specific things are the GLYPHS and the flat fill colour; there is NO
      # bespoke layout. Both hearts live in ONE contiguous `white-space: pre` block
      # (subject + braille gap + channel) exactly like a chart's row block, so the
      # whole widget is sized by `.pito-metric__chart` just like every chart.
      #
      # FATNESS is the one tunable: the heart canvas COLS×ROWS (+ GAP cells between
      # the two hearts). Total width = 2·COLS + GAP must stay ≤ a chart's width so
      # it never clips on portrait. Tune these (and only these) here.
      #
      # Empty-area treatment (owner-locked = OUTLINE): below the waterline a heart
      # is SOLID in its colour; above it only the rim glyphs survive (interior
      # blanked) and the row's that-heart sub-span is dimmed — a hollow heart above
      # the fill. Driven by the per-cell state from Pito::Analytics::BrailleHeart.
      #
      # Pure inputs (the builder computes + persists these so re-render needs no
      # refetch): `hearts` (1–2 × { score:, color:, likes:, dislikes: }) and the
      # pre-rendered `caption`.
      class HeartChartComponent < BaseComponent
        REVEAL_CONTROLLER = "pito--area-chart-reveal"

        # Heart canvas (CELLS) — the fatness knob. Slim by default; total width
        # 2·COLS + GAP = 37 ≤ the area chart's width, so it fits portrait.
        HEART_COLS = 17
        HEART_ROWS = 12 # canvas 2 rows taller; the heart is inset (down 1 row) by BrailleHeart
        GAP_CELLS  = 3

        BLANK = [ 0x2800 ].pack("U")

        COLOR_TOKENS = {
          red:    "var(--accent-red)",
          purple: "var(--accent-purple)",
          pink:   "var(--accent-pink)"
        }.freeze

        # @param hearts  [Array<Hash>] 1–2 hearts, each
        #   { score: 0..100, color: :red|:purple, likes: Integer, dislikes: Integer }
        # @param caption [String] pre-rendered, html-safe caption (BaseComponent)
        def initialize(hearts:, caption:, cols: HEART_COLS, rows: HEART_ROWS, gap: GAP_CELLS)
          super(caption:)
          @hearts = Array(hearts)
          @hcols  = cols.to_i
          @hrows  = rows.to_i
          @gap    = gap.to_i
        end

        def reveal_controller = REVEAL_CONTROLLER

        # Total widget width in CELLS = the AREA CHART width (BaseComponent::COLS),
        # so the heart caption spreads in exactly the same space as a chart caption
        # — REGARDLESS of 1 or 2 hearts. The heart(s) are centred in this width and
        # the surplus is blank (the faint bg grid shows through).
        def canvas_cols = cols

        # The braille gap between two hearts (width-preserving blank cells).
        def gap = BLANK * @gap

        # Left / right blank padding (strings) that centre the heart content within
        # the full canvas width.
        def pad_left  = BLANK * left_pad
        def pad_right = BLANK * (canvas_cols - content_cols - left_pad)

        # Background grid matches the heart canvas: full width × the heart's row
        # count (fewer than the chart box). bg_cols defaults to `cols` (== canvas).
        def bg_rows_count = @hrows

        # One row per canvas row (top→bottom). Each row entry is an array of the
        # per-heart sub-cells { glyphs:, fill:, color: } — the template lays them out
        # as pad_left + sub-span(heart1) + gap + sub-span(…) + pad_right inside a
        # single `.pito-metric__hrow`. Interior/outside cells are BLANK so the faint
        # bg grid shows through (hollow heart + graph-paper surround).
        def combined_rows
          data = hearts_data
          Array.new(@hrows) do |i|
            data.map { |h| h[:rows][i].merge(color: h[:color]) }
          end
        end

        # Per-heart legend rows: { color:, likes:, dislikes:, pct_label: }.
        def legends
          hearts_data.map { |h| h.slice(:color, :likes, :dislikes, :pct_label) }
        end

        private

        # Width (cells) the hearts + inter-heart gaps occupy before centring.
        def content_cols
          n = @hearts.size
          (n * @hcols) + ([ n - 1, 0 ].max * @gap)
        end

        def left_pad
          [ (canvas_cols - content_cols) / 2, 0 ].max
        end

        public

        private

        # Render each heart once (memoised) into { color:, likes:, dislikes:,
        # pct_label:, rows: [{ fill:, glyphs: }] }.
        def hearts_data
          @hearts_data ||= @hearts.map do |h|
            grid = Pito::Analytics::BrailleHeart.call(score: h[:score], cols: @hcols, rows: @hrows)
            {
              color:     color_token(h[:color]),
              likes:     h[:likes].to_i,
              dislikes:  h[:dislikes].to_i,
              pct_label: pct_label(h[:score]),
              rows:      grid.map { |row| render_row(row) }
            }
          end
        end

        # A row → { fill: (any solid cell?), glyphs: (rim+fill glyphs, blanks for
        # hollow interior/outside) }. The braille blank keeps every column's width.
        def render_row(row)
          has_filled  = row.any? { |c| c[:state] == :filled }
          has_outline = row.any? { |c| c[:state] == :outline }
          {
            # Dim (is-outline) ONLY a pure-RIM row (outline glyphs, no fill); never
            # a blank margin/interior row — so a 100% heart stays fully solid.
            fill:   has_filled || !has_outline,
            glyphs: row.map { |c| %i[filled outline].include?(c[:state]) ? c[:char] : BLANK }.join
          }
        end

        def color_token(sym)
          COLOR_TOKENS.fetch(sym&.to_sym, COLOR_TOKENS[:red])
        end

        def pct_label(score)
          format("%.1f%%", score.to_f.clamp(0.0, 100.0))
        end
      end
    end
  end
end
