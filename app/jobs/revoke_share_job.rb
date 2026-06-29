# frozen_string_literal: true

# Asynchronously deletes a Share record (by the source event's id).
# Idempotent: if the Share is already gone (never existed / already deleted),
# `find_by` returns nil and `&.destroy!` is a no-op.
#
# Enqueued by Pito::Share::UniversalActions when the owner types
# `#<handle> revoke` or `#<handle> unshare` on a shared event.
class RevokeShareJob < ApplicationJob
  queue_as :default

  def perform(event_id)
    ::Share.find_by(event_id: event_id)&.destroy!
  end
end
