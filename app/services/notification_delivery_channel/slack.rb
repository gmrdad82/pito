# Phase 16 §1 — Notifications data model + delivery channels.
#
# Slack webhook channel. Mirror of `Discord` — different credentials
# key, different `delivered_at_column`, different formatter target
# (Spec 02). Same retry semantics: 2xx ok, 4xx (non-429) terminal,
# 5xx / 429 / network transient.
class NotificationDeliveryChannel
  class Slack < NotificationDeliveryChannel
    def enabled?
      AppSetting.slack_delivery_enabled?
    end

    def webhook_url
      Rails.application.credentials.dig(:notifications, :slack_webhook_url)
    end

    def delivered_at_column
      :slack_delivered_at
    end

    # Spec 01 stub. Spec 02 swaps in the block-kit builder
    # (`NotificationFormatter::Slack.payload_for(notification)`).
    def payload_for(notification)
      if defined?(NotificationFormatter::Slack)
        NotificationFormatter::Slack.payload_for(notification)
      else
        { "text" => notification.title.to_s }
      end
    end

    def perform_post(url, payload)
      uri = URI(url)
      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = (uri.scheme == "https")
      request = Net::HTTP::Post.new(uri.request_uri,
                                    "Content-Type" => "application/json")
      request.body = payload.to_json
      http.request(request)
    end
  end
end
