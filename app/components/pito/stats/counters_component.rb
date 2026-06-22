# frozen_string_literal: true

module Pito
  module Stats
    # A row of stat counters — middot-separated, alignable left or center.
    # Pure presentation: the caller supplies the metrics (key + raw value);
    # the value is compacted and the label/icon comes from Pito::Stats::Metrics
    # so it stays consistent everywhere. subs / vids / views render as
    # "<value> <Word>"; likes / comms render as "<value>👍" / "<value>💬".
    #
    #   render(Pito::Stats::CountersComponent.new(
    #     metrics: [{ key: :views, value: 454 }, { key: :likes, value: 3 }],
    #     align: :left
    #   ))  #=> "454 Views · 3👍"
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
        key   = metric[:key].to_sym
        count = tag.span(Pito::Formatter::CompactCount.call(metric[:value]), class: "text-fg")

        body =
          if Pito::Stats::Metrics.icon?(key)
            # "<count>👍" — count then inline icon, no separating space.
            safe_join([ count, icon_for(key) ])
          else
            # "<count> <Word>" — count, space, dimmed full word.
            safe_join([ count, " ", tag.span(Pito::Stats::Metrics.label(key), class: "text-fg-dim") ])
          end

        tag.span(body, class: "pito-stats-counters__cell")
      end

      def icon_for(key)
        tag.span(
          render(Pito::IconComponent.new(name: Pito::Stats::Metrics.icon(key), label: Pito::Stats::Metrics.label(key))),
          class: "text-fg-dim"
        )
      end

      def align_class
        ALIGN.fetch(@align, ALIGN[:left])
      end
    end
  end
end
