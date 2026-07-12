# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # A labelled visualization block inside an :ai message — an optional dim
      # label line above one of the kwargs-pure house visualizers. The braille
      # glyph renderers are the product: the model supplies VALUES, these
      # components draw them.
      #
      #   sparkline        → Analytics::Visualizers::Sparkline (2-row braille)
      #   chart viz=area   → Analytics::Visualizers::Area — the full ticked
      #                      chart (y tick values, date/index x-axis, optional
      #                      green target line), via its generic kwargs
      #   chart viz=bar    → Analytics::Visualizers::Bar (≤5 labelled bars)
      #   chart viz=heatmap→ Analytics::Visualizers::Heatmap (2..42 values,
      #                      optional 1:1 labels; weekday preset at a bare 7)
      #   score            → Pito::ScoreBarComponent (0–100 gradient bar)
      #   ttb              → Pito::TimeToBeatComponent (hours gauge)
      class VizBlockComponent < ViewComponent::Base
        # @param block [Hash] one normalized Ai::Blocks row (string keys)
        def initialize(block:)
          @block = block
        end

        def label
          @block["label"].presence
        end

        def viz_component
          case @block["type"]
          when "sparkline" then sparkline(@block)
          when "chart"     then chart(@block)
          when "score"
            Pito::ScoreBarComponent.new(score: @block["value"], label: label, show_label: label.present?)
          when "ttb"       then ttb(@block)
          end
        end

        private

        def sparkline(block)
          Pito::Analytics::Visualizers::Sparkline.new(
            series: block["series"], series_max: block["series_max"]
          )
        end

        def chart(block)
          case block["viz"]
          when "area"    then area(block)
          when "bar"     then Pito::Analytics::Visualizers::Bar.new(bars: symbolized_bars(block), caption: "")
          when "heatmap" then heatmap(block)
          when "heart"   then heart(block)
          end
        end

        # 2..42 equal-width heat columns; `labels` (nil-safe) pair 1:1 with
        # values — nil at exactly 7 values wears the weekday preset ticks.
        def heatmap(block)
          Pito::Analytics::Visualizers::Heatmap.new(
            values: block["values"], labels: block["labels"], caption: ""
          )
        end

        # One heart, red (the AI palette's only heart color), filled to the
        # 0–100 score with the likes/dislikes legend.
        def heart(block)
          Pito::Analytics::Visualizers::Heart.new(
            hearts:  [ { score: block["score"], color: :red,
                         likes: block["likes"], dislikes: block["dislikes"] } ],
            caption: ""
          )
        end

        def area(block)
          Pito::Analytics::Visualizers::Area.new(
            series:       block["series"],
            target_daily: block["target"].to_f,
            caption:      "",
            dates:        block["dates"],
            value_format: block["format"].presence || :count
          )
        end

        def ttb(block)
          current = block["current"]
          Pito::TimeToBeatComponent.new(
            levels:  Array(block["levels"]).map { |l| { label: l["label"], hours: l["hours"] } },
            current: current && { label: current["label"], hours: current["hours"] }
          )
        end

        # The house bucket ramp (mirrors the analyze builder's GEO_RAMP — the
        # same 5 hues the native breakdown bars cycle through). The model never
        # picks colors (style stays in the app); each bucket gets its own hue.
        BAR_RAMP = %i[green cyan blue purple orange].freeze

        def symbolized_bars(block)
          Array(block["bars"]).each_with_index.map do |bar, i|
            { label: bar["label"], pct: bar["pct"], value_label: bar["value_label"],
              color: BAR_RAMP[i % BAR_RAMP.size] }.compact
          end
        end
      end
    end
  end
end
