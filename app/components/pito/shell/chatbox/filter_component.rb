# frozen_string_literal: true

module Pito
  module Shell
    module Chatbox
      # Renders a filter item: a keyboard shortcut (via ShortcutComponent) followed
      # by a value rendered as a PLAIN .pito-token span via TokenComponent (owner
      # 17.4 — scope chips no longer shimmer). The chat-form Stimulus controller
      # finds the inner span via .pito-token to update the displayed value when
      # cycling channels/periods.
      class FilterComponent < ViewComponent::Base
        def initialize(shortcut:, value:)
          @shortcut = shortcut
          @value    = value
        end
      end
    end
  end
end
