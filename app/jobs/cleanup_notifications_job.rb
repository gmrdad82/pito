# frozen_string_literal: true

# P59 — Daily cleanup of read notifications.
#
# Hard-deletes every Notification whose `read_at` is non-NULL and older
# than RETENTION_PERIOD (7 days). Unread notifications are never touched.
#
# Uses `delete_all` (not `destroy_all`) to skip ActiveRecord callbacks
# and avoid unnecessary broadcasts on a bulk cron path.
class CleanupNotificationsJob < ApplicationJob
  queue_as :default

  RETENTION_PERIOD = 7.days

  def perform
    cutoff  = RETENTION_PERIOD.ago
    deleted = Notification.where.not(read_at: nil).where(read_at: ..cutoff).delete_all
    Rails.logger.info(
      "CleanupNotificationsJob: deleted #{deleted} read notification#{'s' unless deleted == 1} " \
      "older than #{RETENTION_PERIOD.inspect}"
    )
    deleted
  end
end
