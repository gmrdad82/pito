# frozen_string_literal: true

# Nightly auto-purge: finds UNNAMED conversations with no activity in
# the last 30 days and requests an async deletion for EACH one individually
# through the SAME path the `dd` keybinding uses (Conversation::RequestDeletion →
# DeleteConversationJob) — NOT a single bulk destroy (which would hold a long
# lock). It only selects + per-id enqueues, mirroring the atomic-jobs fan-out of
# NightlyReindexJob.
#
# NAMED conversations are never selected (Conversation.purgeable rejects them via
# the same `named?` predicate the app uses), so a custom-named conversation is
# safe and stays until the user deletes it.
#
# Scheduled daily via config/recurring.yml (alongside the nightly roster).
class PurgeUnnamedConversationsJob < ApplicationJob
  queue_as :default

  def perform
    Conversation.purgeable.each do |conversation|
      Conversation::RequestDeletion.call(conversation: conversation)
    end
  end
end
