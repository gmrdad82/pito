# frozen_string_literal: true

module Pito
  module Keybinding
    # Renders a single keyboard shortcut token in canonical yellow bold styling.
    # Single source of truth for the `font-bold text-yellow` shortcut appearance.
    # The diagonal yellow→orange shimmer's staggered offset comes from the shared
    # Pito::Shimmer.offset_class so it never re-derives the bucket math by hand.
    class ShortcutComponent < ViewComponent::Base
      def initialize(keys:, data: {})
        @keys = keys
        @data = data
      end

      def call
        tag.span(@keys, class: "font-bold text-yellow pito-kbd-shimmer #{Pito::Shimmer.offset_class(@keys)}", **data_attrs)
      end

      private

      def data_attrs
        return {} if @data.empty?

        @data.transform_keys { |k| :"data-#{k}" }
      end
    end
  end
end
