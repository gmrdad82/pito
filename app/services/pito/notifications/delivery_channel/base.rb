# Phase 16 §1 → Phase 26 01b refactor. PORO dispatcher base.
#
# Originally `NotificationDeliveryChannel` was a top-level PORO whose
# subclasses (`Slack`, `Discord`, `InApp`) handled per-provider HTTP
# dispatch. Phase 26 introduces an Active Record model at
# `app/models/notification_delivery_channel.rb` — the data layer for
# per-provider webhook configuration (URL + routing flags +
# `last_validated_at`). The PORO dispatcher logic lives in THIS class
# (`Pito::Notifications::DeliveryChannel::Base`) so the canonical
# constant `NotificationDeliveryChannel` can be the AR model.
#
# Subclasses implement `enabled?`, `webhook_url`, `delivered_at_column`,
# `payload_for(notification)`, and `perform_post(url, payload)`. The
# base owns retry-aware bookkeeping (stamping `*_delivered_at`,
# recording `last_error`, bumping `retry_count`) and the
# 2xx / 4xx / 5xx classification.
#
# Phase 26 refactor: subclasses now resolve `webhook_url` via the AR
# model first (`NotificationDeliveryChannel.send(kind)`) and fall back
# to `ENV["PITO_<KIND>_WEBHOOK_URL"]`. This preserves backward
# compatibility with installs that wired the URL through the
# environment only.
require "net/http"

module Pito
  module Notifications
    module DeliveryChannel
      class Base
        # Re-raised after `record_failure!` ran for 5xx / 429 / network so
        # `deliver`'s general `rescue StandardError` does not double-record.
        class TransientFailure < StandardError; end

        # Delivery outcome for callers (the scheduler / job) to inspect.
        Result = Struct.new(:status, :reason, keyword_init: true)

        def self.for(kind)
          case kind.to_s
          when "discord" then Pito::Notifications::DeliveryChannel::Discord.new
          when "slack"   then Pito::Notifications::DeliveryChannel::Slack.new
          when "in_app"  then Pito::Notifications::DeliveryChannel::InApp.new
          else
            raise ArgumentError, "unknown channel: #{kind.inspect}"
          end
        end

        # Returns a `Result` on success / skip / terminal failure.
        # Raises StandardError on transient failure so Sidekiq retries.
        def deliver(notification)
          return Result.new(status: :skipped, reason: :disabled) unless enabled?
          return Result.new(status: :skipped, reason: :already_delivered) if already_delivered?(notification)

          payload = payload_for(notification)
          response = perform_post(webhook_url, payload)
          code = response.code.to_i

          case code
          when 200..299
            stamp_delivered!(notification)
            Result.new(status: :ok)
          when 429
            # Record once, raise so Sidekiq retries.
            record_failure!(notification, "HTTP 429: rate limited")
            raise TransientFailure, "rate limited"
          when 400..499
            record_failure!(notification, "HTTP #{code}: #{response.body.to_s.first(500)}")
            # Terminal — swallow so Sidekiq does NOT retry.
            Result.new(status: :failed, reason: :terminal)
          else
            record_failure!(notification, "HTTP #{code}")
            raise TransientFailure, "HTTP #{code}"
          end
        rescue TransientFailure
          raise
        rescue StandardError => e
          # Catch-all for unexpected raises (e.g., network errors raised by
          # perform_post). Record once, then re-raise so Sidekiq retries.
          record_failure!(notification, e.message)
          raise
        end

        # Subclass interface (must override):
        def enabled?
          raise NotImplementedError
        end

        def webhook_url
          raise NotImplementedError
        end

        def delivered_at_column
          raise NotImplementedError
        end

        def payload_for(_notification)
          raise NotImplementedError
        end

        def perform_post(_url, _payload)
          raise NotImplementedError
        end

        # Subclass override: returns true iff the configured `webhook_url`
        # points at a host the channel trusts. Default implementation rejects
        # everything so subclasses MUST opt-in via an explicit allowlist.
        def deliverable_url?(_url)
          false
        end

        private

        # Hoisted from the per-channel `perform_post` so both Discord and
        # Slack inherit identical timeout settings (F2). Tuned for webhook
        # POSTs: short open / ssl handshake, longer read / write to allow
        # the remote to ack a small JSON body.
        def configure_http(http)
          http.open_timeout  = 5
          http.read_timeout  = 10
          http.write_timeout = 10
          http.ssl_timeout   = 5
          http
        end

        def already_delivered?(notification)
          notification.read_attribute(delivered_at_column).present?
        end

        def stamp_delivered!(notification)
          notification.update!(
            delivered_at_column => Time.current,
            :last_error => nil
          )
        end

        def record_failure!(notification, message)
          notification.update!(
            last_error: message.to_s.first(1000),
            retry_count: notification.retry_count + 1
          )
        end
      end
    end
  end
end
