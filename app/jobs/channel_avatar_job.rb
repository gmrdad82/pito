# frozen_string_literal: true

# Caches a channel's avatar locally (ActiveStorage) from its YouTube source URL.
#
# Enqueued from ChannelInfoJob after a channel sync. Runs off the request/sync
# path so a slow or rate-limited (429) CDN fetch never blocks the sync, and a
# transient failure can retry. Idempotent: re-running re-attaches the latest.
class ChannelAvatarJob < ApplicationJob
  queue_as :default

  def perform(channel_id, source_url)
    channel = ::Channel.find_by(id: channel_id)
    return unless channel

    Channel::Avatar::Ingest.new(channel:, source_url:).call
  end
end
