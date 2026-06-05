# frozen_string_literal: true

module Pito
  module Table
    # Renders a single key/value row: a cyan key span + a dim value span.
    #
    # Used in:
    #   - keybinding/table_component — fixed w-44 key column, flex gap-4
    #   - event/expandable_body_component — flex gap-4, w-40 key, w-20 value right-aligned
    #   - event/system_component — grid grid-cols-[max-content_1fr] gap-x-2 gap-y-1 rows
    #   - event/error_component — credential label/value rows
    #
    # The caller controls layout (grid vs flex) at the container level.
    # This component renders only the two spans.
    #
    # @param key_text    [String]  the key/label text
    # @param value_text  [String]  the value text
    # @param key_class   [String]  classes for the key span (default: "text-cyan whitespace-nowrap")
    # @param value_class [String]  classes for the value span (default: "text-fg-dim")
    # @param wrapper_class [String, nil] if present, wraps both spans in a div with these classes
    class KeyValueRowComponent < ViewComponent::Base
      DEFAULT_KEY_CLASS   = "text-cyan whitespace-nowrap"
      DEFAULT_VALUE_CLASS = "text-fg-dim"

      def initialize(key_text:, value_text:, key_class: DEFAULT_KEY_CLASS, value_class: DEFAULT_VALUE_CLASS, wrapper_class: nil)
        @key_text      = key_text
        @value_text    = value_text
        @key_class     = key_class
        @value_class   = value_class
        @wrapper_class = wrapper_class
      end

      def call
        key_span   = tag.span(@key_text,   class: @key_class)
        value_span = tag.span(@value_text, class: @value_class)

        if @wrapper_class.present?
          tag.div(class: @wrapper_class) { key_span + value_span }
        else
          key_span + value_span
        end
      end
    end
  end
end
