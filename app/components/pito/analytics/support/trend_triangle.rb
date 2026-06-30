# frozen_string_literal: true

module Pito
  module Analytics
    module Support
      # A filled-triangle TREND indicator that rides ON a metric value (e.g. the
      # `841K▲` in a Views caption): ▲ up (green), ▼ down (red), – steady
      # (shimmering fg-default). When there is NO comparable baseline (a lifetime
      # window, or no prior data at all) it renders NOTHING — you can't trend
      # against nothing — so callers get just the bare value.
      #
      # Trend resolution reuses `Pito::Analytics::Trend.for` (current vs the prior
      # comparable window). Views is higher-is-better, so a rise is good/green.
      #
      # Builders that compose raw caption markup use the `.html` class method
      # (renders without a view context, like Pito::Shimmer::TokenComponent.html):
      #   Pito::Analytics::Support::TrendTriangle.html(value: 841_000, previous: 700_000)
      class TrendTriangle < ViewComponent::Base
        GLYPHS = { up: "▲", down: "▼", steady: "–" }.freeze

        # html-safe <span> (or empty buffer when there's no triangle to show), for
        # string call sites that splice it next to a value token.
        def self.html(value:, previous:)
          new(value:, previous:).html
        end

        def initialize(value:, previous:)
          @value    = value
          @previous = previous
        end

        # No triangle for a neutral/no-baseline trend — the value stands alone.
        def render? = GLYPHS.key?(trend)

        def call = html

        def html
          return ActiveSupport::SafeBuffer.new unless render?

          ActionController::Base.helpers.tag.span(
            GLYPHS.fetch(trend), class: css_class, data: { trend: trend }, aria: { hidden: true }
          )
        end

        # One of :up, :down, :steady, :neutral.
        def trend
          @trend ||= resolve
        end

        private

        def resolve
          return :neutral if @value.nil?

          direction = Pito::Analytics::Trend.for(current: @value, previous: @previous)
          direction == :none ? :neutral : direction # :none = no prior → no triangle
        end

        def css_class
          base = "pito-metric__trend pito-trend-number"
          return base if trend == :neutral

          "#{base} pito-trend-number--#{trend} #{Pito::Shimmer.offset_class(GLYPHS.fetch(trend))}"
        end
      end
    end
  end
end
