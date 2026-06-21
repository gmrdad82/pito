# frozen_string_literal: true

module Pito
  module Shell
    module Chatbox
      # Renders a filter item: a keyboard shortcut (yellow, via ShortcutComponent)
      # followed by a value rendered as a pito-token-shimmer span via TokenComponent.
      # The chat-form Stimulus controller finds the inner span via .pito-token-shimmer
      # to update the displayed value when cycling channels/periods.
      class FilterComponent < ViewComponent::Base
        def initialize(shortcut:, value:)
          @shortcut = shortcut
          @value    = value
        end
      end
    end
  end
end
