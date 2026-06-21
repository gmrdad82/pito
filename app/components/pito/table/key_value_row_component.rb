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
    # @param value_text  [String]  the value text (ignored when value_component: is given)
    # @param key_class   [String]  classes for the key span (default: "text-cyan whitespace-nowrap")
    # @param value_class [String]  classes for the value span (default: "text-fg-dim")
    # @param value_component [ViewComponent::Base, nil] render this component in the value cell
    #   instead of a plain span — the seam that lets callers drop a shimmer token
    #   (Pito::Shimmer::TokenComponent) in without inlining its classes.
    # @param wrapper_class [String, nil] if present, wraps both spans in a div with these classes
    # @param key_data    [Hash]    extra data-* attributes for the key span (e.g. typewriter target)
    # @param value_data  [Hash]    extra data-* attributes for the value span
    class KeyValueRowComponent < ViewComponent::Base
      DEFAULT_KEY_CLASS   = "text-cyan whitespace-nowrap"
      DEFAULT_VALUE_CLASS = "text-fg-dim"

      def initialize(key_text:, value_text: nil, key_class: DEFAULT_KEY_CLASS, value_class: DEFAULT_VALUE_CLASS, value_component: nil, wrapper_class: nil, key_data: {}, value_data: {})
        @key_text        = key_text
        @value_text      = value_text
        @key_class       = key_class
        @value_class     = value_class
        @value_component = value_component
        @wrapper_class   = wrapper_class
        @key_data        = key_data
        @value_data      = value_data
      end

      def call
        key_span   = tag.span(@key_text, class: @key_class, **span_attrs(@key_data))
        value_span =
          if @value_component
            render(@value_component)
          else
            tag.span(@value_text, class: @value_class, **span_attrs(@value_data))
          end

        if @wrapper_class.present?
          tag.div(class: @wrapper_class) { key_span + value_span }
        else
          key_span + value_span
        end
      end

      private

      # Converts a hash of data attributes into keyword args for tag helpers.
      # e.g. { "pito--typewriter-target" => "prose" } → { data: { "pito--typewriter-target" => "prose" } }
      # Pass an empty hash to produce no extra attributes.
      def span_attrs(data_hash)
        data_hash.present? ? { data: data_hash } : {}
      end
    end
  end
end
