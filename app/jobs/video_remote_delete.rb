# Phase 21 — hard-delete a video on YouTube after the local Video row
# has already been destroyed. Because the local row is gone by the time
# this runs, we take the YouTube id + the YoutubeConnection id directly
# rather than a video_id: there is nothing left to look up.
#
# Guards a missing / reauth-needed connection the same way
# `VideoRemoteStatusSync` does, then issues the 50-unit
# `videos.delete` through `VideosClient#delete_video`, passing a throwaway
# struct that only carries the YouTube id.
#
# Failure posture mirrors the status-sync job's rescue ladder.
class VideoRemoteDelete < ApplicationJob
  queue_as :default

  RemoteVideo = Struct.new(:youtube_video_id)

  def perform(youtube_video_id, connection_id)
    return if youtube_video_id.blank?

    connection = YoutubeConnection.find_by(id: connection_id)
    return if connection.nil?
    return if connection.needs_reauth?

    Channel::Youtube::VideosClient.new(connection).delete_video(
      RemoteVideo.new(youtube_video_id)
    )
  rescue Channel::Youtube::QuotaExhaustedError => e
    Rails.logger.warn("[video-remote-delete] quota exceeded for youtube video #{youtube_video_id}: #{e.message}")
    raise
  rescue Channel::Youtube::AuthRevokedError => e
    connection&.update_columns(needs_reauth: true) if connection
    Rails.logger.warn("[video-remote-delete] auth revoked for youtube video #{youtube_video_id}: #{e.message}")
  rescue Channel::Youtube::ValidationError => e
    Rails.logger.warn("[video-remote-delete] youtube rejected delete for #{youtube_video_id}: #{e.message}")
    # Non-retriable.
  rescue Channel::Youtube::NotFoundError => e
    Rails.logger.warn("[video-remote-delete] youtube video #{youtube_video_id} not found: #{e.message}")
    # Non-retriable — already gone on YouTube.
  rescue Channel::Youtube::ServerError => e
    Rails.logger.warn("[video-remote-delete] server error for youtube video #{youtube_video_id}: #{e.message}")
    raise
  rescue *network_error_classes => e
    Rails.logger.warn("[video-remote-delete] network error for youtube video #{youtube_video_id}: #{e.class}: #{e.message}")
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
