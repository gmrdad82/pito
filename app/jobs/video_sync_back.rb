# Phase 12 — write-side video sync job. Pulls a Video, reads the
# YouTube-side state via VideosReader (1 unit), then PUTs the local
# writable subset via VideosClient (50 units). On success, stamps
# `last_synced_at`, `etag`, and `made_for_kids_effective`; clears
# `last_sync_error`. On failure, surfaces the error to the Video row
# via `last_sync_error` and (depending on the failure class) re-raises
# so Sidekiq retries with backoff.
#
# Per locked decision Q9: read-modify-write the full snippet+status
# parts every save (Note 1's destructive-PUT-per-part warning). The
# read costs 1 unit; the write costs 50 units. Total per call: 51.
#
# Per locked decision Q10: failure is OPTIMISTIC. The local
# `privacy_status` is NOT rolled back on sync-back failure — the
# user sees `last_sync_error` and re-edits.
class VideoSyncBack
  include Sidekiq::Job

  sidekiq_options queue: "default", retry: 3

  def perform(video_id)
    video = Video.find_by(id: video_id)
    return unless video

    connection = video.channel.youtube_connection
    return mark_no_connection(video) if connection.nil?
    return mark_needs_reauth(video) if connection.needs_reauth?

    fresh = Youtube::VideosReader.new(connection).read_video(video)
    payload = Youtube::VideosClient.new(connection).update_video(video, fresh: fresh)

    new_etag = payload.is_a?(Hash) ? payload[:etag] : nil
    made_for_kids_effective_value = payload.is_a?(Hash) ? payload.dig(:status, :madeForKids) : nil

    video.update_columns(
      etag: new_etag.presence || video.etag,
      last_synced_at: Time.current,
      last_sync_error: nil,
      made_for_kids_effective: made_for_kids_effective_value.nil? ? video.made_for_kids_effective : made_for_kids_effective_value
    )
  rescue Youtube::QuotaExhaustedError => e
    record_error(video, "youtube quota exceeded; will retry: #{e.message}")
    raise # let Sidekiq retry with backoff
  rescue Youtube::AuthRevokedError => e
    connection&.update_columns(needs_reauth: true) if connection
    record_error(video, "youtube connection needs re-auth: #{e.message}")
  rescue Youtube::ValidationError => e
    record_error(video, "youtube rejected the update: #{e.message}")
    # Non-retriable — re-sending the same payload won't succeed.
  rescue Youtube::NotFoundError => e
    record_error(video, "video not found on youtube: #{e.message}")
    # Non-retriable.
  rescue Youtube::ServerError => e
    record_error(video, "youtube server error: #{e.message}")
    raise # let Sidekiq retry
  rescue *network_error_classes => e
    record_error(video, "network error: #{e.class}: #{e.message}")
    raise # let Sidekiq retry
  end

  private

  def mark_no_connection(video)
    record_error(video, "no youtube connection on this video's channel")
  end

  def mark_needs_reauth(video)
    record_error(video, "youtube connection needs re-auth")
  end

  def record_error(video, message)
    return unless video
    video.update_columns(last_sync_error: message)
  end

  def network_error_classes
    [
      ::Errno::ECONNREFUSED, ::Errno::ETIMEDOUT, ::Errno::EHOSTUNREACH,
      ::SocketError, ::Net::OpenTimeout, ::Net::ReadTimeout, ::EOFError
    ]
  end
end
