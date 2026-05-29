# frozen_string_literal: true

module Pito
  module Segment
    class Component < ViewComponent::Base
      # @param border [String, nil] CSS border shorthand (e.g. "1px solid var(--accent-orange)").
      #   The bar element renders this as its background color; the content wrapper gets no border.
      #   When nil, the bar is hidden (display: none).
      # @param background [String, nil] CSS background for the content wrapper (e.g. "var(--bg-surface)").
      #   When nil, the content area is transparent.
      def initialize(border: nil, background: nil)
        @border = border
        @background = background
      end
    end
  end
end
