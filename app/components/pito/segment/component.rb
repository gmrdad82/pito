# frozen_string_literal: true

module Pito
  module Segment
    class Component < ViewComponent::Base
      # @param accent [Symbol, nil] Accent color for the left bar:
      #   :orange, :red, :yellow, :purple. When nil, the bar is omitted.
      # @param background [String, nil] CSS background for the content wrapper
      #   (e.g. "var(--bg-surface)"). When nil, the content area is transparent.
      def initialize(accent: nil, background: nil, id: nil, scrollback_message: false)
        @accent = accent
        @background = background
        @id = id
        @scrollback_message = scrollback_message
      end
    end
  end
end
