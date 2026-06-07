# Phase 12 — write-side video sync job. Pulls a Video, reads the
# YouTube-side state via VideosReader (1 unit), then PUTs the local
# writable subset via VideosClient (50 units). On success, stamps
# `last_synced_at` and `etag`. On failure, logs the error and
# (depending on the failure class) re-raises so the job retries with
# backoff.
#
# Per locked decision Q9: read-modify-write the full snippet+status
# parts every save (Note 1's destructive-PUT-per-part warning). The
# read costs 1 unit; the write costs 50 units. Total per call: 51.
#
# Per locked decision Q10: failure is OPTIMISTIC. The local
# `privacy_status` is NOT rolled back on sync-back failure.
class VideoSyncBack < ApplicationJob
  queue_as :default

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    connection = video.channel.youtube_connection
    return if connection.nil?
    return if connection.needs_reauth?

    # Phase 11 §01a reserved hook — thumbnail YouTube push-back
    # (parent open question §4). When the deferred follow-up lands,
    # call `Channel::Youtube::ThumbnailsClient.new(connection).set_thumbnail(video)`
    # here BEFORE the `update_video` call so the thumbnail bytes land
    # alongside the writable-subset PUT. Today the thumbnail stays
    # local-only via Active Storage; this comment is the bookmark.

    fresh = Channel::Youtube::VideosReader.new(connection).read_video(video)
    payload = Channel::Youtube::VideosClient.new(connection).update_video(video, fresh: fresh)

    new_etag = payload.is_a?(Hash) ? payload[:etag] : nil

    video.update_columns(
      etag: new_etag.presence || video.etag,
      last_synced_at: Time.current
    )
  rescue Channel::Youtube::QuotaExhaustedError => e
    Rails.logger.warn("[video-sync-back] quota exceeded for video #{video_id}: #{e.message}")
    raise
  rescue Channel::Youtube::AuthRevokedError => e
    connection&.update_columns(needs_reauth: true) if connection
    Rails.logger.warn("[video-sync-back] auth revoked for video #{video_id}: #{e.message}")
  rescue Channel::Youtube::ValidationError => e
    Rails.logger.warn("[video-sync-back] youtube rejected update for video #{video_id}: #{e.message}")
    # Non-retriable — re-sending the same payload won't succeed.
  rescue Channel::Youtube::NotFoundError => e
    Rails.logger.warn("[video-sync-back] video #{video_id} not found on youtube: #{e.message}")
    # Non-retriable.
  rescue Channel::Youtube::ServerError => e
    Rails.logger.warn("[video-sync-back] server error for video #{video_id}: #{e.message}")
    raise
  rescue *network_error_classes => e
    Rails.logger.warn("[video-sync-back] network error for video #{video_id}: #{e.class}: #{e.message}")
    raise
  end

  private

  def network_error_classes
    [
      ::Errno::ECONNREFUSED, ::Errno::ETIMEDOUT, ::Errno::EHOSTUNREACH,
      ::SocketError, ::Net::OpenTimeout, ::Net::ReadTimeout, ::EOFError
    ]
  end
end
