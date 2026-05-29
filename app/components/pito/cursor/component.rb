# frozen_string_literal: true

module Pito
  module Cursor
    class Component < ViewComponent::Base
      # @param char [String] the character to render (default "/", the pito cursor glyph).
      # @param color [String] CSS color value for the cursor fill (default fg-default).
      # @param ghost [Boolean] render as outline rectangle, solid on parent hover.
      def initialize(char: "/", color: "var(--fg-default)", ghost: false)
        @char = char
        @color = color
        @ghost = ghost
      end

      def ghost?
        @ghost
      end
    end
  end
end
