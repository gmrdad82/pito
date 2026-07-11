# frozen_string_literal: true

module Pito
  module Event
    module Ai
      # A prose block inside an :ai message — escaped monospace text, newlines
      # preserved. Stray markdown emphasis the model leaks (**bold**, `code`,
      # leading #-headers) is stripped to plain text: structure belongs in
      # typed blocks, never in markup.
      class TextBlockComponent < ViewComponent::Base
        def initialize(text:)
          @text = strip_markdown(text.to_s)
        end

        attr_reader :text

        def call
          tag.div(text, class: "whitespace-pre-wrap text-fg")
        end

        private

        def strip_markdown(value)
          value
            .gsub(/\*\*(.+?)\*\*/m, '\1')
            .gsub(/`([^`\n]*)`/, '\1')
            .gsub(/^#+\s+/, "")
        end
      end
    end
  end
end
