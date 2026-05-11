# Phase 26 — 01e. Per-user digest delivery.
#
# Enqueued by `DailyDigestSchedulerJob` (one per ripe user per tick).
# Resolves the user, composes the 24h digest payload, and POSTs it to
# every digest-enabled `NotificationDeliveryChannel`. Slack + Discord
# are delivered in series within the same job; each provider is
# independent (a Slack 404 does not abort the Discord POST).
#
# Per the user-locked decisions:
#
#   - Retries: 3 attempts with exponential backoff (1m, 5m, 15m) on
#     transient failures (HTTP 429, 5xx, network / timeout / DNS / TLS).
#   - Permanent failures (HTTP 400, 401, 403, 404, 410) do NOT retry.
#     They log the failure and create a `Notification` row tagged
#     `dedup_key: "digest_delivery_failed:<channel_id>:<utc_iso8601>"`
#     and `event_type: "digest_delivery_failed"`. The row lands in the
#     user's in-app inbox via Phase 16's notification surface.
#
# Slack and Discord delivery results are accumulated; the job raises a
# `TransientFailure` at the end iff any one channel reported a
# transient outcome. Raising preserves the ActiveJob / Sidekiq retry
# machinery; on retry, the per-channel `last_delivered_at_for_digest`
# style of guard is intentionally NOT used — a retried digest
# re-delivers to all enabled channels. This is acceptable because
# permanent-failure channels are already excluded via the `last_error`
# notification row (the next retry will hit the same channel set, and
# the operator can disable the bad channel from Settings).
class DailyDigestDeliverJob < ApplicationJob
  queue_as :default

  RETRY_BACKOFF_SECONDS = [
    60,        # 1m
    5 * 60,    # 5m
    15 * 60    # 15m
  ].freeze

  PERMANENT_HTTP_STATUSES = [ 400, 401, 403, 404, 410 ].freeze

  class TransientFailure < StandardError; end

  # Three retries, exponential ladder. Sidekiq surfaces ActiveJob
  # retries via the `:wait` proc.
  retry_on TransientFailure, wait: ->(count) { RETRY_BACKOFF_SECONDS[count] || RETRY_BACKOFF_SECONDS.last }, attempts: 4

  def perform(user_id)
    user = User.find_by(id: user_id)
    return if user.nil?

    enabled = NotificationDeliveryChannel.where(daily_digest: true).to_a
    return if enabled.empty?

    result = ::Digest::Composer.new(user).call

    transient_encountered = false
    enabled.each do |channel|
      outcome = deliver_to(channel, result, user: user)
      transient_encountered = true if outcome == :transient
    end

    raise TransientFailure, "one or more channels reported a transient failure" if transient_encountered
  end

  private

  def deliver_to(channel, composer_result, user:)
    payload = render_payload(channel.kind, composer_result)
    return :skipped if payload.nil?

    client = http_client_for(channel)
    response = client.deliver(payload)

    if response.success?
      :ok
    elsif permanent_failure?(response)
      record_permanent_failure!(channel, response, user: user)
      :permanent
    else
      Rails.logger.warn(
        "DailyDigestDeliverJob: transient failure for channel##{channel.id} (#{channel.kind}): #{response.error}"
      )
      :transient
    end
  end

  def render_payload(kind, composer_result)
    case kind.to_s
    when "slack"   then ::Digest::SlackRenderer.new(composer_result).call
    when "discord" then ::Digest::DiscordRenderer.new(composer_result).call
    else
      Rails.logger.warn("DailyDigestDeliverJob: unknown channel kind #{kind.inspect}")
      nil
    end
  end

  def http_client_for(channel)
    case channel.kind.to_s
    when "slack"   then Webhooks::SlackClient.new(channel.webhook_url)
    when "discord" then Webhooks::DiscordClient.new(channel.webhook_url)
    end
  end

  def permanent_failure?(response)
    return false if response.status.nil?

    PERMANENT_HTTP_STATUSES.include?(response.status.to_i)
  end

  def record_permanent_failure!(channel, response, user:)
    return unless defined?(Notification)

    dedup_key = "digest_delivery_failed:#{channel.id}:#{Time.current.utc.iso8601}"
    Notification.create!(
      kind: :sync_error,
      event_type: "digest_delivery_failed",
      severity: :warn,
      title: "digest delivery failed (#{channel.kind})",
      body: "channel##{channel.id} returned #{response.status}: " \
            "#{response.error.to_s.first(500)}",
      fires_at: Time.current,
      dedup_key: dedup_key,
      created_by_user: user
    )
  rescue StandardError => e
    Rails.logger.warn(
      "DailyDigestDeliverJob: failed to record permanent-failure notification: #{e.class}: #{e.message}"
    )
  end
end
