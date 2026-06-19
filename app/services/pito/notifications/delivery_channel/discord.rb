# Discord webhook channel.
#
# Reads the active webhook URL from the AR row first
# (`NotificationDeliveryChannel.discord&.webhook_url`) and falls back to
# `ENV["PITO_DISCORD_WEBHOOK_URL"]`. POSTs JSON. Treats 2xx as success,
# 4xx (except 429) as terminal, 5xx + 429 + network errors as transient
# (Sidekiq retries via the raise; the base class records the failure on
# the row first).
#
# Payload formatting lives in
# `Pito::Notifications::Formatter::Discord`. Spec 01 ships a minimal
# payload (`{ content: title }`) so the channel is testable end-to-end
# before the formatter lands.
module Pito
  module Notifications
    module DeliveryChannel
      class Discord < Base
        # Webhook URL must point at one of these hosts. Anything else
        # (including loopback, internal IPs, attacker-owned domains) is
        # rejected by `deliverable_url?` so a misconfigured credential can
        # never exfiltrate notification content (F3).
        DISCORD_HOSTS = %w[discord.com discordapp.com].freeze

        def enabled?
          return false unless AppSetting.discord_delivery_enabled?

          url = webhook_url
          return false if url.blank?

          unless deliverable_url?(url)
            Rails.logger.warn(
              "Pito::Notifications::DeliveryChannel::Discord disabled: " \
              "webhook URL not in DISCORD_HOSTS allowlist"
            )
            return false
          end

          true
        end

        def webhook_url
          # AR row first, ENV var as fallback.
          row_url = NotificationDeliveryChannel.discord&.webhook_url
          return row_url if row_url.present?

          ENV["PITO_DISCORD_WEBHOOK_URL"].presence
        end

        def delivered_at_column
          :discord_delivered_at
        end

        # Spec 01 stub. Spec 02 swaps in the rich-embed builder.
        def payload_for(notification)
          if defined?(Pito::Notifications::Formatter::Discord)
            Pito::Notifications::Formatter::Discord.payload_for(notification)
          else
            { "content" => notification.title.to_s }
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
          uri.is_a?(URI::HTTPS) && DISCORD_HOSTS.include?(uri.host)
        rescue URI::InvalidURIError
          false
        end
      end
    end
  end
end
