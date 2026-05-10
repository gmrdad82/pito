# Phase 16 §3 UX restructure 2026-05-10 — read-notification cleanup.
#
# Sidekiq cron entry (`config/sidekiq_cron.yml` → `notification_cleanup`):
# runs daily at 03:30 UTC. Hard-deletes every Notification whose
# `in_app_read_at` is non-NULL and older than 7 days.
#
# Why hard-delete: the row's only purpose after read is the audit trail
# for the user who marked it read. Per the single-shared-inbox model
# (Spec 01 Q1) there's no per-user state — once any user has read the
# row, it stays read forever. After 7 days the historic value is gone
# and the row's just inbox clutter, so we delete.
#
# `delete_all` (NOT `destroy_all`) because:
#   - There are no dependent associations to cascade.
#   - The row's after_destroy_commit broadcast triggers the badge
#     replace; on a bulk delete that broadcast fires N times
#     unnecessarily. `delete_all` skips callbacks.
#   - The badge re-renders on the next page load anyway; live update
#     latency on a cron path is irrelevant.
class NotificationCleanupJob < ApplicationJob
  queue_as :default

  RETENTION_PERIOD = 7.days

  def perform
    cutoff  = RETENTION_PERIOD.ago
    deleted = Notification.where("in_app_read_at IS NOT NULL AND in_app_read_at < ?", cutoff).delete_all
    Rails.logger.info("NotificationCleanupJob: deleted #{deleted} read notification#{'s' if deleted != 1} older than #{RETENTION_PERIOD.inspect}")
    deleted
  end
end
