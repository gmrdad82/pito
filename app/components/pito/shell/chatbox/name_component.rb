# frozen_string_literal: true

module Pito
  module Shell
    module Chatbox
      # The purple conversation name shown before the chatbox filter hints.
      #
      # Wrapped in a stable `#pito-chatbox-conversation-name` slot so a rename can
      # update it live over the conversation's Turbo Stream: it appears when the
      # conversation goes Unnamed → named, updates when the title changes, and
      # disappears if the name is cleared. `display: contents` keeps the slot from
      # adding any layout of its own, so the name + separator flow exactly as
      # before.
      class NameComponent < ViewComponent::Base
        SLOT_ID = "pito-chatbox-conversation-name"

        # @param title [String, nil] the display name when the conversation is
        #   named (see Conversation#named?), or nil when Unnamed.
        def initialize(title:)
          @title = title.presence
        end

        attr_reader :title

        def slot_id
          SLOT_ID
        end

        def named?
          @title.present?
        end
      end
    end
  end
end
