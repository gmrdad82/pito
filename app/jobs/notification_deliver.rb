# Notifications data model + delivery channels.
#
# Deliver a single Notification through a single channel.
# Argument shape: `(notification_id, channel_kind)` where `channel_kind`
# is one of `"discord"` / `"slack"` / `"in_app"`. Resolves the channel
# via `NotificationDeliveryChannel.for(...)` and invokes `deliver`.
#
class NotificationDeliver < ApplicationJob
  queue_as :default

  def perform(notification_id, channel_kind)
    notification = Notification.find_by(id: notification_id)
    # Row was deleted between enqueue and run — silent no-op.
    return if notification.nil?

    channel = NotificationDeliveryChannel.for(channel_kind)
    channel.deliver(notification)
  end
end
