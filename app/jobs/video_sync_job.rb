# frozen_string_literal: true

# Full per-channel YouTube video sync — the SINGLE per-channel sync job.
# Imports new/private uploads AND reconciles existing videos (attribute updates
# + hard-delete of uploads removed on YouTube) via `Pito::Sync::VideoLibrary#sync`,
# then emits a per-channel `VideoSync` summary Notification (quiet when nothing
# changed).
#
# Turn-less; errors are rescued + logged so a single channel never aborts the
# nightly fan-out.
#
# Enqueued by: `NightlySyncJob` (one per connected channel). The chat sync/import
# tools call `Pito::Sync::VideoLibrary#sync` directly because they broadcast a
# chat summary instead of creating a notification.
class VideoSyncJob < ApplicationJob
  queue_as :default

  def perform(channel_id)
    channel = ::Channel.find_by(id: channel_id)
    return unless channel
    return if channel.youtube_connection_id.nil?
    return if channel.youtube_connection.needs_reauth?

    result = ::Pito::Sync::VideoLibrary.new(channel).sync
    ::Pito::Notifications::Source::VideoSync.report!(scope_label: channel.handle, result:)
  rescue StandardError => e
    Rails.logger.error("VideoSyncJob: failed for channel=#{channel_id}: #{e.class}: #{e.message}")
  end
end
