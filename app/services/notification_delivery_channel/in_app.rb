# Phase 16 §1 — Notifications data model + delivery channels.
#
# In-app channel — a synchronous no-op. The "in-app delivery" itself
# is the Notification row's existence. Exists for symmetry so the
# scheduler + tests can iterate channels uniformly.
class NotificationDeliveryChannel
  class InApp < NotificationDeliveryChannel
    def enabled?
      true
    end

    def webhook_url
      nil
    end

    def delivered_at_column
      nil
    end

    # Override `deliver` because the base class flow assumes an HTTP
    # POST. The in-app channel does no HTTP, no column stamp, no
    # error recording — the row's existence IS the delivery.
    def deliver(_notification)
      Result.new(status: :ok)
    end

    def payload_for(_notification)
      {}
    end

    def perform_post(_url, _payload)
      raise NotImplementedError, "InApp channel does not POST"
    end
  end
end
