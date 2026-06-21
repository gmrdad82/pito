# frozen_string_literal: true

module Pito
  module Stats
    # The italic, dimmed legend mapping stat abbreviations to words, e.g.
    # "S subs, D vids, V views". Entries + order come from the caller; the
    # abbreviation + word come from Pito::Stats::Metrics. Alignable.
    #
    #   render(Pito::Stats::LegendComponent.new(metrics: [:subs, :vids, :views], align: :center))
    class LegendComponent < ViewComponent::Base
      ALIGN = { left: "text-left", center: "text-center" }.freeze

      def initialize(metrics:, align: :left)
        @metrics = Array(metrics)
        @align   = align.to_sym
      end

      def render?
        @metrics.any?
      end

      def call
        entries = @metrics.map.with_index do |key, i|
          entry = safe_join([
            tag.span(Pito::Stats::Metrics.abbr(key), class: "pito-stats-legend__abbr"),
            " ",
            Pito::Stats::Metrics.label(key)
          ])
          i.zero? ? entry : safe_join([ ", ", entry ])
        end
        tag.p(safe_join(entries), class: "pito-stats-legend text-fg-dim italic #{align_class}")
      end

      private

      def align_class
        ALIGN.fetch(@align, ALIGN[:left])
      end
    end
  end
end
