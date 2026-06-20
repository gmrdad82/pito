# frozen_string_literal: true

# Delivers a Notification's message to any configured outbound webhooks
# (Slack, Discord), formatting the message per platform via
# `Pito::Notifications::WebhookFormatter`.
#
# Enqueued by `Notification#after_create_commit`. Each platform delivery is
# isolated: a blank URL skips that platform, and a delivery failure (the
# client `Result` is not `success?`, or a StandardError is raised) is logged
# and never aborts the other platform or the job.
class NotificationWebhookDeliverJob < ApplicationJob
  queue_as :default

  def perform(notification_id)
    notification = Notification.find_by(id: notification_id)
    # Row was deleted between enqueue and run — silent no-op.
    return if notification.nil?

    deliver_slack(notification)
    deliver_discord(notification)
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
end
