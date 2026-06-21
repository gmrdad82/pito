# frozen_string_literal: true

module Pito
  module Keybinding
    # Renders a single keyboard shortcut token in canonical yellow bold styling.
    # Single source of truth for the `font-bold text-yellow` shortcut appearance.
    class ShortcutComponent < ViewComponent::Base
      # Number of staggered animation-delay buckets (.pito-kbd-shimmer-dN in
      # application.css). Each shortcut picks a bucket from a stable hash of its
      # text so different shortcuts shimmer out of phase (never synchronised),
      # while a given shortcut stays consistent across renders.
      OFFSETS = 5

      def initialize(keys:, data: {})
        @keys = keys
        @data = data
      end

      def call
        tag.span(@keys, class: "font-bold text-yellow pito-kbd-shimmer #{offset_class}", **data_attrs)
      end

      private

      def offset_class
        "pito-kbd-shimmer-d#{@keys.to_s.bytes.sum % OFFSETS}"
      end

      def data_attrs
        return {} if @data.empty?

        @data.transform_keys { |k| :"data-#{k}" }
      end
    end
  end
end
