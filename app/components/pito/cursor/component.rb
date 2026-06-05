# frozen_string_literal: true

module Pito
  module Cursor
    class Component < ViewComponent::Base
      # @param char [String] the character to render (default "/", the pito cursor glyph).
      # @param color [String] CSS color value for the cursor fill (default fg-default).
      def initialize(char: "/", color: "var(--fg-default)")
        @char = char
        @color = color
      end
    end
  end
end
