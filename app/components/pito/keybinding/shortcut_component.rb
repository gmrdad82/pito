# frozen_string_literal: true

module Pito
  module Keybinding
    # Renders a single keyboard shortcut token in canonical yellow bold styling.
    # Single source of truth for the `font-bold text-yellow` shortcut appearance.
    # The diagonal yellow→orange shimmer's staggered offset comes from the shared
    # Pito::Shimmer.offset_class so it never re-derives the bucket math by hand.
    class ShortcutComponent < ViewComponent::Base
      # `kbd_click:` (default true) wires the pito--kbd-click controller so a tap
      # synthesizes the keystroke. Pass `kbd_click: false` to skip that wiring and
      # use only the caller-supplied `data:` (e.g. the meta-line shift+r hint,
      # which prefills the reply handle via pito--chat-prefill instead of
      # synthesizing a keydown). Styling is identical either way.
      def initialize(keys:, data: {}, kbd_click: true)
        @keys      = keys
        @data      = data
        @kbd_click = kbd_click
      end

      def call
        tag.span(@keys, class: "font-bold text-yellow pito-kbd-shimmer #{Pito::Shimmer.offset_class(@keys)}", **data_attrs)
      end

      private

      # Always wire the pito--kbd-click controller so every shortcut hint is
      # tappable on touch (tap == pressing the key). This adds behavior only —
      # no styling. Any caller-supplied `data:` is merged in; `controller` and
      # `action` are concatenated (Stimulus allows multiple) so a hint can carry
      # both pito--kbd-click and, say, pito--platform-key at once.
      def data_attrs
        return @data.transform_keys { |k| :"data-#{k}" } unless @kbd_click

        base = {
          "controller" => "pito--kbd-click",
          # mousedown#hold keeps the chatbox focused (no blur / mobile-keyboard
          # dismiss when a hint is tapped); click#fire synthesizes the keystroke.
          "action" => "mousedown->pito--kbd-click#hold click->pito--kbd-click#fire",
          "pito--kbd-click-key-value" => @keys
        }

        merged = base.merge(@data) do |key, base_val, data_val|
          %w[controller action].include?(key) ? "#{base_val} #{data_val}" : data_val
        end

        merged.transform_keys { |k| :"data-#{k}" }
      end
    end
  end
end
