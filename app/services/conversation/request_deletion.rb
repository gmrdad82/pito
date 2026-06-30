# frozen_string_literal: true

# Requests an ASYNC deletion of a conversation: marks it in-flight (deleting_at),
# swaps its sidebar row to the shimmering-dots placeholder everywhere
# (pito:global), and hands the potentially-slow turns/events cascade to
# DeleteConversationJob.
#
# Single source of truth shared by the `dd` keybinding
# (ConversationsController#destroy) and the nightly auto-purge of unnamed
# conversations (PurgeUnnamedConversationsJob), so the two paths never drift —
# the purge deletes ONE conversation at a time through this exact path rather
# than a bulk destroy (which would hold a long lock).
#
# Idempotent: a conversation already marked for deletion is a no-op (no second
# job is enqueued), so the nightly sweep can safely re-run.
#
# NAMESPACE: reopens the ::Conversation model namespace (mirroring
# Conversation::Rename) — `Conversation` here is the model.
class Conversation
  module RequestDeletion
    module_function

    # @param conversation [Conversation] the conversation to delete.
    # @return [Conversation] the same conversation (now marked deleting).
    def call(conversation:)
      return conversation if conversation.deleting?

      conversation.update!(deleting_at: Time.current)
      Pito::Stream::Broadcaster.broadcast_global_conversation_row(conversation:)
      DeleteConversationJob.perform_later(conversation.id)

      conversation
    end
  end
end
