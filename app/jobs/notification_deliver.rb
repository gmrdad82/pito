# Phase 16 §1 — Notifications data model + delivery channels.
#
# Sidekiq job: deliver a single Notification through a single channel.
# Argument shape: `(notification_id, channel_kind)` where `channel_kind`
# is one of `"discord"` / `"slack"` / `"in_app"`. Resolves the channel
# via `NotificationDeliveryChannel.for(...)` and invokes `deliver`.
#
# Retry posture (Q11): exponential ladder 1m / 5m / 15m / 1h / 6h with
# `retry: 5` so after the 5th transient failure, the channel column
# stays NULL forever, `last_error` carries the final reason. The
# in-app row remains visible regardless — webhook failures do not
# affect inbox visibility.
class NotificationDeliver
  include Sidekiq::Job

  RETRY_LADDER_SECONDS = [
    60,        # 1m
    5  * 60,   # 5m
    15 * 60,   # 15m
    60 * 60,   # 1h
    6  * 3600  # 6h
  ].freeze

  sidekiq_options queue: "default", retry: 5

  sidekiq_retry_in do |count, _exception, _ctx|
    RETRY_LADDER_SECONDS[count] || RETRY_LADDER_SECONDS.last
  end

  def perform(notification_id, channel_kind)
    notification = Notification.find_by(id: notification_id)
    # Row was deleted between enqueue and run — silent no-op.
    return if notification.nil?

    channel = NotificationDeliveryChannel.for(channel_kind)
    channel.deliver(notification)
  end
end
