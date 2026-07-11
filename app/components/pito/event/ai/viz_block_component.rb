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
      #   chart viz=area   → the same braille area engine (the full ticked Area
      #                      chart joins once its metric preset is generalized)
      #   chart viz=bar    → Analytics::Visualizers::Bar (≤5 labelled bars)
      #   chart viz=heatmap→ Analytics::Visualizers::Heatmap (7 weekday values)
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
          when "area"    then sparkline(block)
          when "bar"     then Pito::Analytics::Visualizers::Bar.new(bars: symbolized_bars(block), caption: "")
          when "heatmap" then Pito::Analytics::Visualizers::Heatmap.new(values: block["values"], caption: "")
          end
        end

        def ttb(block)
          hours = block["hours"] || {}
          Pito::TimeToBeatComponent.new(
            hours: {
              main:          hours["main"].to_f,
              extras:        hours["extras"].to_f,
              completionist: hours["completionist"].to_f
            },
            footage_hours: block["footage_hours"].to_f
          )
        end

        def symbolized_bars(block)
          Array(block["bars"]).map do |bar|
            { label: bar["label"], pct: bar["pct"], value_label: bar["value_label"] }.compact
          end
        end
      end
    end
  end
end
