# frozen_string_literal: true

module Pito
  module Stats
    # A row of stat counters — "<value> <ABBR>" per metric, middot-separated,
    # alignable left or center. Pure presentation: the caller supplies the
    # metrics (key + raw value); the value is compacted and the abbreviation
    # comes from Pito::Stats::Metrics so it stays consistent everywhere.
    #
    #   render(Pito::Stats::CountersComponent.new(
    #     metrics: [{ key: :views, value: 454 }, { key: :likes, value: 3 }],
    #     align: :left
    #   ))
    class CountersComponent < ViewComponent::Base
      ALIGN = { left: "text-left", center: "text-center" }.freeze

      def initialize(metrics:, align: :left)
        @metrics = Array(metrics)
        @align   = align.to_sym
      end

      def render?
        @metrics.any?
      end

      def call
        parts = []
        @metrics.each_with_index do |metric, i|
          parts << render(Pito::Shell::InlineSeparatorComponent.new) if i.positive?
          parts << cell(metric)
        end
        tag.div(safe_join(parts), class: "pito-stats-counters #{align_class}")
      end

      private

      def cell(metric)
        tag.span(
          safe_join([
            tag.span(Pito::Formatter::CompactCount.call(metric[:value]), class: "text-fg"),
            " ",
            tag.span(Pito::Stats::Metrics.abbr(metric[:key]), class: "text-fg-dim")
          ]),
          class: "pito-stats-counters__cell"
        )
      end

      def align_class
        ALIGN.fetch(@align, ALIGN[:left])
      end
    end
  end
end
