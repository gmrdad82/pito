# Phase 16 §1 — Notifications data model + delivery channels.
#
# Sidekiq cron entry: every minute. Walks the calendar for ripe
# notification dispatch declarations, materializes Notification rows
# (idempotent via the unique partial index on `notifications`), and
# enqueues per-channel delivery jobs.
class NotificationSchedulerJob < ApplicationJob
  queue_as :default

  def perform
    Pito::Notifications::Scheduler.new.perform
  end
end
