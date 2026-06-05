# Phase 26 — 01g. Viewer-time analytics implementation.
#
# Daily fan-out job. Enumerates every video belonging to a channel
# with an active YouTube connection and enqueues a
# `VideoViewerTimeSyncJob` per video.
#
# Picks T-1 worth of buckets per inner job; the rolling-90-day window
# is provided by the `pito:backfill_viewer_time_buckets` rake task,
# not by this orchestrator.
class ViewerTimeDailyRefreshJob < ApplicationJob
  queue_as :analytics

  def perform
    Video
      .joins(channel: :youtube_connection)
      .where(youtube_connections: { needs_reauth: false })
      .find_each(batch_size: 100) do |video|
        VideoViewerTimeSyncJob.perform_later(video.id)
      end
  end
end
