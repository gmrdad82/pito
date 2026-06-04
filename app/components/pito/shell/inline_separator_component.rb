# frozen_string_literal: true

module Pito
  module Shell
    # A middot "·" divider with the canonical faded color + horizontal margin.
    # Replaces ad-hoc <span class="text-fg-faded mx-2">·</span> spans wherever
    # inline items need a separator (chatbox filter row, mini status).
    class InlineSeparatorComponent < ViewComponent::Base
      def call
        tag.span("·", class: "text-fg-faded mx-2")
      end
    end
  end
end
