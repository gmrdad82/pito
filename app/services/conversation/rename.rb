# frozen_string_literal: true

# Renames a conversation and broadcasts the change everywhere the name shows:
#   - the chatbox conversation-name slot (Unnamed→named makes the purple name
#     appear; a rename updates it), on the conversation's own stream;
#   - the global conversations-sidebar row, so other instances/tabs update live.
#
# Single source of truth shared by ConversationsController#rename (the /resume
# sidebar edit) and the `/rename` slash command, so the two never drift.
#
# NAMESPACE: this reopens the ::Conversation model namespace (mirroring
# Channel::Avatar::Ingest under ::Channel) — `Conversation` here is the model.
class Conversation
  module Rename
    module_function

    # @param conversation [Conversation] the conversation to rename.
    # @param title        [String]       the new title (caller validates presence).
    # @return [Conversation] the renamed conversation.
    def call(conversation:, title:)
      conversation.update!(title: title)

      Pito::Stream::Broadcaster.new(conversation:).broadcast_conversation_name(
        title: (conversation.named? ? conversation.display_name : nil)
      )
      Pito::Stream::Broadcaster.broadcast_global_conversation_row(conversation:)

      conversation
    end
  end
end
