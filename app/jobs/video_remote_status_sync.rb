# Focused, status-only write-back job. Pulls a Video, reads
# the YouTube-side state via VideosReader (1 unit), then PUTs the local
# state via VideosClient (50 units) BUT restricted to the privacy/schedule
# fields only — `fields: [:privacy_status, :publish_at]`. YouTube's own
# title/description round-trip untouched: pito never writes those back.
#
# This replaces the dead full-subset write-back job, which pushed
# title/description + status. The user does NOT want title/description
# synced to YouTube, only the publish state.
#
# On success, stamps `last_synced_at`. On failure, logs the error and
# (depending on the failure class) re-raises so the job retries with
# backoff.
#
# Failure is OPTIMISTIC: the local `privacy_status` is NOT rolled back on
# write-back failure.
class VideoRemoteStatusSync < ApplicationJob
  queue_as :default

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    connection = video.channel.youtube_connection
    return if connection.nil?
    return if connection.needs_reauth?

    fresh = Channel::Youtube::VideosReader.new(connection).read_video(video)
    Channel::Youtube::VideosClient.new(connection).update_video(
      video, fresh: fresh, fields: [ :privacy_status, :publish_at ]
    )

    video.update_columns(last_synced_at: Time.current)
  rescue Channel::Youtube::QuotaExhaustedError => e
    Rails.logger.warn("[video-remote-status-sync] quota exceeded for video #{video_id}: #{e.message}")
    raise
  rescue Channel::Youtube::AuthRevokedError => e
    connection&.update_columns(needs_reauth: true) if connection
    Rails.logger.warn("[video-remote-status-sync] auth revoked for video #{video_id}: #{e.message}")
  rescue Channel::Youtube::ValidationError => e
    Rails.logger.warn("[video-remote-status-sync] youtube rejected update for video #{video_id}: #{e.message}")
    # Non-retriable — re-sending the same payload won't succeed. Surface it so the
    # confirmation's "Timer set" doesn't silently lie about a write that never landed.
    surface_rejection(video)
  rescue Channel::Youtube::NotFoundError => e
    Rails.logger.warn("[video-remote-status-sync] video #{video_id} not found on youtube: #{e.message}")
    # Non-retriable. Surface it — the local state changed but YouTube never did.
    surface_rejection(video)
  rescue Channel::Youtube::ServerError => e
    Rails.logger.warn("[video-remote-status-sync] server error for video #{video_id}: #{e.message}")
    raise
  rescue *network_error_classes => e
    Rails.logger.warn("[video-remote-status-sync] network error for video #{video_id}: #{e.class}: #{e.message}")
    raise
  end

  private

  # Drop an unread Notification so the operator learns a YouTube write-through was
  # rejected — the local privacy/schedule change stuck, but YouTube never accepted
  # it, so any "done / Timer set" outcome would otherwise be a silent lie.
  def surface_rejection(video)
    return unless video

    Notification.create!(
      message: Pito::Copy.render("pito.copy.videos.sync_rejected", title: video.title)
    )
  end

  def network_error_classes
    [
      ::Errno::ECONNREFUSED, ::Errno::ETIMEDOUT, ::Errno::EHOSTUNREACH,
      ::SocketError, ::Net::OpenTimeout, ::Net::ReadTimeout, ::EOFError
    ]
  end
end
