# Phase 16 §1 — Notifications data model + delivery channels.
#
# Slack webhook channel. Mirror of `Discord` — different credentials
# key, different `delivered_at_column`, different formatter target
# (Spec 02). Same retry semantics: 2xx ok, 4xx (non-429) terminal,
# 5xx / 429 / network transient.
class NotificationDeliveryChannel
  class Slack < NotificationDeliveryChannel
    # Webhook URL must point at one of these hosts (F3). Slack publishes
    # incoming webhooks under a single host; anything else is a
    # misconfiguration we should refuse rather than POST notification
    # bodies to.
    SLACK_HOSTS = %w[hooks.slack.com].freeze

    def enabled?
      return false unless AppSetting.slack_delivery_enabled?

      url = webhook_url
      return false if url.blank?

      unless deliverable_url?(url)
        Rails.logger.warn(
          "NotificationDeliveryChannel::Slack disabled: " \
          "webhook URL not in SLACK_HOSTS allowlist"
        )
        return false
      end

      true
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
      configure_http(http)
      request = Net::HTTP::Post.new(uri.request_uri,
                                    "Content-Type" => "application/json")
      request.body = payload.to_json
      http.request(request)
    end

    def deliverable_url?(url)
      uri = URI.parse(url.to_s)
      uri.is_a?(URI::HTTPS) && SLACK_HOSTS.include?(uri.host)
    rescue URI::InvalidURIError
      false
    end
  end
end
