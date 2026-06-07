# frozen_string_literal: true

module Pito
  module Palette
    module Suggestions
      class Component < ViewComponent::Base
        # @param mode [Symbol] :slash or :hashtag — controls bar accent and echo-char.
        # @param items [Array<Hash>] each with keys :label, :description, :masked.
        # @param selected_index [Integer] index of the highlighted row.
        # @param typed [String] what the user has typed so far (shown on the echo line).
        def initialize(mode:, items:, selected_index: 0, typed: "")
          @mode = mode
          @items = Array(items)
          @selected_index = selected_index
          @typed = typed
        end

        # Returns the data-accent value for the segment bar.
        def bar_accent
          @mode == :hashtag ? "cyan" : "purple"
        end

        # Returns the leading character shown on the cursor-echo line.
        def echo_char
          @mode == :hashtag ? "#" : "/"
        end
      end
    end
  end
end
