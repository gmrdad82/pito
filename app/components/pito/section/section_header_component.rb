# frozen_string_literal: true

module Pito
  module Section
    # A bold section title in yellow or orange with canonical mb-1 spacing.
    #
    # Used in:
    #   - sidebar/section_component         — orange, no px
    #   - palette/ctrl_k/section_component  — yellow, px-[7px]
    #   - sidebar/conversations/component   — orange, no px  (×2: Recent / Older)
    #   - keybinding/table_component        — yellow, no px
    #
    # @param text       [String]            the title string (already translated by caller)
    # @param color      [:yellow, :orange]  the text colour token (default: :yellow)
    # @param px         [String, nil]       optional horizontal padding, e.g. "[7px]"
    # @param mb         [String]            bottom margin value (default: "1")
    # @param extra_attrs [Hash]             extra HTML attributes for the span (e.g. data-*)
    class SectionHeaderComponent < ViewComponent::Base
      COLOR_CLASS = {
        yellow: "text-yellow",
        orange: "text-orange"
      }.freeze

      def initialize(text:, color: :yellow, px: nil, mb: "1", extra_attrs: {})
        @text        = text
        @color       = color
        @px          = px
        @mb          = mb
        @extra_attrs = extra_attrs
      end

      def call
        classes = [
          COLOR_CLASS.fetch(@color, COLOR_CLASS[:yellow]),
          "font-bold",
          "mb-#{@mb}"
        ]
        classes << "px-#{@px}" if @px.present?

        tag.div(@text, class: classes.join(" "), **@extra_attrs)
      end
    end
  end
end
