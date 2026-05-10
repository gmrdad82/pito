# Phase 16 §1 — Notifications data model + delivery channels.
#
# Base class for the per-channel webhook delivery dispatch. Subclasses
# implement `enabled?`, `webhook_url`, `delivered_at_column`,
# `payload_for(notification)`, and `perform_post(url, payload)`. The
# base owns retry-aware bookkeeping (stamping `*_delivered_at`,
# recording `last_error`, bumping `retry_count`) and the
# 2xx / 4xx / 5xx classification.
#
# Channels are POROs, NOT models — configuration is install-level
# (credentials + AppSetting flags) so there's nothing to persist about
# the channel itself. See Q3 in
# `docs/plans/beta/16-notifications/specs/01-notification-data-model-and-delivery.md`.
require "net/http"

class NotificationDeliveryChannel
  # 4xx-but-non-429 outcomes raise this to abort retry. Sidekiq sees a
  # raised error; the job rescues `PermanentFailure` and returns
  # without re-raising so the retry counter never increments.
  class PermanentFailure < StandardError; end

  # Delivery outcome for callers (the scheduler / job) to inspect.
  Result = Struct.new(:status, :reason, keyword_init: true)

  def self.for(kind)
    case kind.to_s
    when "discord" then NotificationDeliveryChannel::Discord.new
    when "slack"   then NotificationDeliveryChannel::Slack.new
    when "in_app"  then NotificationDeliveryChannel::InApp.new
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
      record_failure!(notification, "HTTP 429: rate limited")
      raise StandardError, "rate limited"
    when 400..499
      record_failure!(notification, "HTTP #{code}: #{response.body.to_s.first(500)}")
      raise PermanentFailure, "HTTP #{code} (terminal)"
    else
      record_failure!(notification, "HTTP #{code}")
      raise StandardError, "HTTP #{code}"
    end
  rescue PermanentFailure
    # Terminal — swallow so Sidekiq does NOT retry. Caller sees a
    # `:failed` result with `:terminal` reason.
    Result.new(status: :failed, reason: :terminal)
  rescue StandardError => e
    record_failure!(notification, e.message) unless e.is_a?(ActiveRecord::RecordInvalid)
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

  private

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
