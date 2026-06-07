# frozen_string_literal: true

# Caches a video's thumbnail locally (ActiveStorage) from its YouTube source URL.
#
# Enqueued per-video from ImportVideosJob + NightlyVideoSyncJob after each upsert.
# Running one job per video spreads the CDN fetches across the queue instead of
# bursting them inline (which is what triggers the 429s), and lets a transient
# failure retry. Idempotent: re-running re-attaches the latest.
class VideoThumbnailJob < ApplicationJob
  queue_as :default

  def perform(video_id, source_url)
    video = ::Video.find_by(id: video_id)
    return unless video

    Video::Thumbnail::Ingest.new(video:, source_url:).call
  end
end
