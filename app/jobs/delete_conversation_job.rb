# frozen_string_literal: true

# Asynchronously destroys a conversation marked for deletion (deleting_at set by
# ConversationsController#destroy). Cascading turns/events can be slow for long
# conversations, so this runs off the request. On success the sidebar row (a
# shimmering-dots placeholder while in flight) is removed everywhere via
# pito:global. On failure the deleting_at flag is cleared so the normal row
# reappears (the delete didn't happen).
class DeleteConversationJob < ApplicationJob
  queue_as :default

  def perform(conversation_id)
    conversation = ::Conversation.find_by(id: conversation_id)
    return unless conversation

    uuid = conversation.uuid
    conversation.destroy!
    Pito::Stream::Broadcaster.broadcast_global_conversation_row_removed(uuid:)
  rescue StandardError => e
    Rails.logger.error("[DeleteConversationJob] #{conversation_id}: #{e.class}: #{e.message}")
    # Restore the row: clear the in-flight flag and re-broadcast the normal row so
    # the user sees the conversation came back (delete did not complete).
    if conversation&.persisted?
      conversation.update_columns(deleting_at: nil)
      Pito::Stream::Broadcaster.broadcast_global_conversation_row(conversation:)
    end
  end
end
