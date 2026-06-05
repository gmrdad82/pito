# frozen_string_literal: true

module Pito
  module Separator
    # A canonical top-divider wrapper or standalone hairline rule.
    #
    # Two rendering modes:
    #
    #   1. **Bordered block** (default when content is passed as a block):
    #      Wraps children in a div with `mt-{spacing} border-t border-{tone} pt-{spacing}`.
    #      The `tone:` param controls the border colour token.
    #      The `spacing:` param controls the mt/pt value (default "1.5").
    #
    #   2. **Standalone hairline** (`hairline: true`):
    #      Renders a `div.h-px bg-line-default` with optional `my-{my}` spacing.
    #
    # Tones:
    #   :default — border-line-default  (opaque divider)
    #   :faded   — border-line-faded    (subtle divider)
    #
    # Examples:
    #   # Bordered block (top divider + padded content below)
    #   render(Pito::Separator::DividerLineComponent.new) do
    #     "content"
    #   end
    #
    #   # Faded bordered block with custom spacing
    #   render(Pito::Separator::DividerLineComponent.new(tone: :faded, spacing: "1.5")) { ... }
    #
    #   # Standalone hairline (like in palette components)
    #   render(Pito::Separator::DividerLineComponent.new(hairline: true))
    #
    class DividerLineComponent < ViewComponent::Base
      BORDER_CLASS = {
        default: "border-line-default",
        faded:   "border-line-faded"
      }.freeze

      # @param tone         [:default, :faded]  border colour token
      # @param spacing      [String]             the mt/pt value, e.g. "1.5" or "2"
      # @param hairline     [Boolean]            render as a standalone h-px rule instead
      # @param my           [String]             vertical margin for hairline mode, e.g. "2"
      # @param extra_classes [String]            additional classes appended to the wrapper
      # @param extra_attrs  [Hash]               extra HTML attributes for the wrapper div
      def initialize(tone: :default, spacing: "1.5", hairline: false, my: nil, extra_classes: nil, extra_attrs: {})
        @tone          = tone
        @spacing       = spacing
        @hairline      = hairline
        @my            = my
        @extra_classes = extra_classes
        @extra_attrs   = extra_attrs
      end

      def call
        if @hairline
          hairline_tag
        else
          bordered_block
        end
      end

      private

      def hairline_tag
        classes = [ "h-px", "bg-line-default" ]
        classes << "my-#{@my}" if @my.present?
        tag.div(class: classes.join(" "))
      end

      def bordered_block
        border = BORDER_CLASS.fetch(@tone, BORDER_CLASS[:default])
        classes = [
          "mt-#{@spacing}",
          "border-t",
          border,
          "pt-#{@spacing}"
        ]
        classes << @extra_classes if @extra_classes.present?
        tag.div(class: classes.join(" "), **@extra_attrs) { content }
      end
    end
  end
end
