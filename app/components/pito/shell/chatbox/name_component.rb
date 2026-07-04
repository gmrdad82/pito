# frozen_string_literal: true

module Pito
  module Shell
    module Chatbox
      # The conversation name in the CONTEXT-METER header (left of the "xx%"
      # counter — the name moved there from the chatbox in 13.39; the Chatbox::
      # namespace is historical).
      #
      # Wrapped in a stable `#pito-chatbox-conversation-name` slot so a rename
      # can update it live over the conversation's Turbo Stream: it appears when
      # the conversation goes Unnamed → named, updates when the title changes,
      # and collapses back to the header spacer when cleared. G44 regression
      # note: this component MUST stay mounted inside ContextMeterComponent —
      # when the meter rendered a bare span instead, broadcast_conversation_name
      # replaced a ghost id and renames only showed after a reload.
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
