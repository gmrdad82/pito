# frozen_string_literal: true

# Delivers a Notification's message to any configured outbound webhooks
# (Slack, Discord) and to every registered FCM device token, formatting the
# webhook message per platform via `Pito::Notifications::WebhookFormatter`
# and the FCM push body as plain text via `Pito::Notifications::PlainMessage`
# (see #deliver_fcm).
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
    # The lockscreen has no HTML renderer: strip markup (and the
    # private_reminder dedup marker riding along as an HTML comment — see
    # Pito::Notifications::PlainMessage) before it ever reaches the Sender.
    # The persisted notification.message is untouched — the marker has to
    # survive there for PrivateReminder's own-day dedup check.
    plain_message = Pito::Notifications::PlainMessage.call(notification.message)
    # notification.title is already app-authored Pito::Copy output, never
    # marker-bearing — it doesn't NEED the strip PlainMessage gives the
    # message body, but running it through anyway costs nothing and keeps
    # both push fields flowing through the one sanctioned strip seam.
    plain_title = Pito::Notifications::PlainMessage.call(notification.title)

    DeviceToken.order(:id).each do |device_token|
      outcome = Pito::Fcm::Sender.new.call(
        token:   device_token.token,
        message: plain_message,
        level:   notification.level,
        title:   plain_title
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
