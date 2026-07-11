# frozen_string_literal: true

module Pito
  module Achievement
    # The MATERIAL RAIL — one tick per ladder step, each tick wearing
    # the EXACT stone (or award metal) that step unlocks, so the next material
    # is always visible:
    #
    #   Subs   [wood][wood][wood][stone]...[NEXT pulsing][dim][dim]  [silver][gold][diamond]
    #   at 2K - next: 5K (Ruby)
    #
    # Reached ticks glow lit in their material; the FIRST unreached tick is the
    # "next" target (bigger, pulsing, titled); everything beyond is dimmed.
    # Channel-subs award steps render as square metal ticks. A legend line
    # names the standing value and the next threshold + material. Full-width,
    # wraps on narrow screens; pure CSS.
    class TrackComponent < ViewComponent::Base
      def initialize(label:, current_value:, scope:, metric:)
        @label         = label
        @current_value = current_value.to_i
        @scope         = scope.to_s
        @metric        = metric.to_s
      end

      def call
        tag.span(class: "pito-shiny-rail") do
          safe_join([ label_span, rail_span, legend_span ].compact)
        end
      end

      private

      def series
        @series ||= Pito::Achievement::Tier.series_for(scope: @scope, metric: @metric)
      end

      def material_for(threshold)
        Pito::Achievement::Tier.material_for(scope: @scope, metric: @metric, threshold:)
      end

      def award?(threshold)
        Pito::Achievement::Tier.award_track?(@scope, @metric) &&
          Pito::Achievement::Tier::AWARDS.key?(threshold)
      end

      def next_threshold
        @next_threshold ||= series.find { |t| t > @current_value }
      end

      def label_span
        tag.span(h(@label), class: "pito-shiny-rail__label")
      end

      def rail_span
        tag.span(class: "pito-shiny-rail__ticks") do
          safe_join(series.map { |t| tick_span(t) })
        end
      end

      def tick_span(threshold)
        classes = [ "pito-shiny-rail__tick" ]
        classes << "pito-shiny-rail__tick--award" if award?(threshold)
        if threshold <= @current_value
          classes << "is-lit"
        elsif threshold == next_threshold
          classes << "is-next"
        else
          classes << "is-dim"
        end
        tag.span("", class: classes.join(" "),
                     title: Pito::Formatter::CompactCount.call(threshold),
                     data: { material: material_for(threshold) })
      end

      # "at 2K - next: 5K (Ruby)" - muted, under the ticks. Omits the next part
      # when the whole ladder is complete.
      def legend_span
        parts = [ "at #{Pito::Formatter::CompactCount.call(@current_value)}" ]
        if next_threshold
          parts << "next: #{Pito::Formatter::CompactCount.call(next_threshold)} (#{material_for(next_threshold).capitalize})"
        end
        tag.span(parts.join(" · "), class: "pito-shiny-rail__legend")
      end
    end
  end
end
