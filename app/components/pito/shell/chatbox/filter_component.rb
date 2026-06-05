# frozen_string_literal: true

module Pito
  module Shell
    module Chatbox
      # Renders a filter item: a keyboard shortcut (yellow, via ShortcutComponent)
      # followed by a value (cyan). The .text-cyan span is required by the
      # chat-form Stimulus controller's cycling hook.
      class FilterComponent < ViewComponent::Base
        def initialize(shortcut:, value:)
          @shortcut = shortcut
          @value    = value
        end
      end
    end
  end
end
