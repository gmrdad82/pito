# Phase 13.2 — Analytics sync engine. Thin wrapper called by the weekly
# cron entry (`youtube_analytics_retention_weekly`). It
# delegates to `YoutubeAnalyticsSync` with `retention_only: true` so
# only V7 retention curves refresh on Monday at 05:00 UTC.
class VideoRetentionSyncOrchestrator < ApplicationJob
  queue_as :analytics

  def perform
    YoutubeAnalyticsSync.new.perform(retention_only: true)
  end
end
