# Phase 13.2 — Analytics sync engine. Top-level Sidekiq orchestrator
# fired by sidekiq-cron at 04:00 UTC. Iterates every active
# `YoutubeConnection`, enqueues per-channel and per-video child jobs.
#
# Per the master-agent decisions:
#
# - Dedicated `analytics` queue.
# - `info`-level start / finish logs; `warn` on auth failure.
# - The 3-day refresh window is `(today_pt - 3 .. today_pt - 1)`.
class YoutubeAnalyticsSync
  include Sidekiq::Job
  sidekiq_options queue: "analytics", retry: false

  LOGGER_TAG = "[analytics-sync]".freeze

  # `retention_only`: when true, enqueue only `VideoRetentionSync`
  # jobs (no daily slices, no window summaries). The weekly cron at
  # `0 5 * * 1` flips this flag via `VideoRetentionSyncOrchestrator`.
  def perform(retention_only: false)
    started = Time.current
    connections = YoutubeConnection.active.to_a
    Rails.logger.info(
      "#{LOGGER_TAG} starting #{retention_only ? 'retention-only ' : 'nightly '}run; #{connections.size} active connections"
    )

    connections.each do |connection|
      dispatch_for(connection, retention_only: retention_only)
    end

    elapsed = (Time.current - started).round(2)
    Rails.logger.info("#{LOGGER_TAG} complete; #{elapsed}s")
  end

  private

  def dispatch_for(connection, retention_only:)
    channels = connection.channels.to_a
    videos = Video
      .joins(:channel)
      .where(channels: { youtube_connection_id: connection.id })

    if retention_only
      active_videos = videos.find_each.select { |v| Youtube::ActiveVideoClassifier.active?(v) }
      active_videos.each { |v| VideoRetentionSync.perform_async(v.id) }
      return
    end

    channels.each { |c| ChannelAnalyticsSync.perform_async(c.id) }
    videos.find_each { |v| VideoAnalyticsSync.perform_async(v.id) }
  end
end
