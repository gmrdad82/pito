# frozen_string_literal: true

# Caches a channel's banner locally (ActiveStorage) from its YouTube source URL
# (brandingSettings.image.banner_external_url).
#
# Enqueued from ChannelInfoJob after a channel sync — off the request/sync path so
# a slow or rate-limited CDN fetch never blocks the sync, and a transient failure
# can retry. Idempotent: re-running re-attaches the latest. Mirrors ChannelAvatarJob.
class ChannelBannerJob < ApplicationJob
  queue_as :default

  def perform(channel_id, source_url)
    channel = ::Channel.find_by(id: channel_id)
    return unless channel

    Channel::Banner::Ingest.new(channel:, source_url:).call
  end
end
