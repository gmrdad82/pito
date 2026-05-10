# Phase 13.2 — Analytics sync engine. Thin wrapper that the weekly
# sidekiq-cron entry (`youtube_analytics_retention_weekly`) fires. It
# delegates to `YoutubeAnalyticsSync` with `retention_only: true` so
# only V7 retention curves refresh on Monday at 05:00 UTC.
class VideoRetentionSyncOrchestrator
  include Sidekiq::Job
  sidekiq_options queue: "analytics", retry: false

  def perform
    YoutubeAnalyticsSync.new.perform(retention_only: true)
  end
end
