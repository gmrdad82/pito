# frozen_string_literal: true

# Delivers a Notification's message to any configured outbound webhooks
# (Slack, Discord) and to every registered FCM device token, formatting the
# webhook message per platform via `Pito::Notifications::WebhookFormatter`.
#
# Enqueued by `Notification#after_create_commit`. Each lane is isolated: a
# blank URL skips that webhook platform, and a delivery failure (the client
# `Result` is not `success?`, or a StandardError is raised) is logged and
# never aborts the other lanes or the job. The FCM lane mirrors that
# isolation per device token — see #deliver_fcm.
class NotificationWebhookDeliverJob < ApplicationJob
  queue_as :default

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    # Row was deleted between enqueue and run — silent no-op.
    return if notification.nil?

    deliver_slack(notification)
    deliver_discord(notification)
    deliver_fcm(notification)
  end

  private

  def deliver_slack(notification)
    url = AppSetting.slack_webhook_url
    return if url.blank?

    payload = Pito::Notifications::WebhookFormatter.slack_payload(notification)
    result  = Pito::Notifications::Webhooks::SlackClient.new(url).deliver(payload)
    return if result.success?

    Rails.logger.warn("[NotificationWebhookDeliverJob] Slack delivery failed: #{result.error}")
  rescue StandardError => e
    Rails.logger.warn("[NotificationWebhookDeliverJob] Slack delivery error: #{e.class}: #{e.message}")
  end

  def deliver_discord(notification)
    url = AppSetting.discord_webhook_url
    return if url.blank?

    payload = Pito::Notifications::WebhookFormatter.discord_payload(notification)
    result  = Pito::Notifications::Webhooks::DiscordClient.new(url).deliver(payload)
    return if result.success?

    Rails.logger.warn("[NotificationWebhookDeliverJob] Discord delivery failed: #{result.error}")
  rescue StandardError => e
    Rails.logger.warn("[NotificationWebhookDeliverJob] Discord delivery error: #{e.class}: #{e.message}")
  end

  # Pushes to every registered device token (id order, for determinism).
  # `Pito::Fcm::Sender#call` never raises — it collapses transport failures,
  # non-2xx responses, and "not configured" into an Outcome — so the
  # per-token branching below is purely on that Outcome:
  #
  #   * unregistered? — FCM says the token is dead (app uninstalled / token
  #     rotated elsewhere). Prune it; keeping it would fail forever.
  #   * disabled?      — FCM isn't configured at all (PITO_FCM_CREDENTIALS_PATH
  #     unset). One disabled outcome means every remaining token would also
  #     come back disabled, so stop iterating instead of learning that N times.
  #   * anything else (success, or a failed-but-not-unregistered outcome) —
  #     the Sender already logged the details of a failure; just move on to
  #     the next token so one dead network moment doesn't skip the rest.
  #
  # The outer rescue mirrors deliver_slack/deliver_discord's isolation: an
  # unexpected error here (e.g. a destroy failure) is logged, not raised, so
  # it can never fail the job.
  def deliver_fcm(notification)
    DeviceToken.order(:id).each do |device_token|
      outcome = Pito::Fcm::Sender.new.call(
        token:   device_token.token,
        message: notification.message,
        level:   notification.level
      )

      if outcome.unregistered?
        Rails.logger.info("[NotificationWebhookDeliverJob] pruning unregistered device token id=#{device_token.id}")
        device_token.destroy
      elsif outcome.disabled?
        break
      end
    end
  rescue StandardError => e
    Rails.logger.warn("[NotificationWebhookDeliverJob] FCM delivery error: #{e.class}: #{e.message}")
  end
end
