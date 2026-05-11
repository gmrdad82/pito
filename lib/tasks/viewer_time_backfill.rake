# Phase 26 §01g — viewer-time backfill rake task.
#
# Walks every owned video and enqueues a `VideoViewerTimeSyncJob` per
# row with the requested `DAYS` window. One-shot, rerunable — the
# inner job is idempotent so re-running over the same window simply
# overwrites the existing buckets.
#
# Usage:
#   bin/rails pito:backfill_viewer_time_buckets
#   bin/rails pito:backfill_viewer_time_buckets DAYS=7
#   bin/rails pito:backfill_viewer_time_buckets DAYS=180
namespace :pito do
  desc "Backfill viewer-time buckets for every owned video. " \
       "DAYS=90 (default) — how many days of buckets to pull per video."
  task backfill_viewer_time_buckets: :environment do
    days = (ENV["DAYS"] || 90).to_i
    if days <= 0
      abort "DAYS must be a positive integer (got #{ENV['DAYS'].inspect})."
    end

    enqueued = 0
    Video
      .joins(channel: :youtube_connection)
      .where(youtube_connections: { needs_reauth: false })
      .find_each(batch_size: 100) do |video|
        VideoViewerTimeSyncJob.perform_async(video.id, days)
        enqueued += 1
      end

    puts "enqueued #{enqueued} viewer-time sync job#{'s' unless enqueued == 1} " \
         "(DAYS=#{days})."
  end
end
