# Phase 16 §1 — Notifications data model + delivery channels.
#
# Master toggles for Discord + Slack webhook delivery on the singleton
# AppSetting row. Both default false; both must be true AND the
# corresponding webhook URL must be present in
# `Rails.application.credentials.notifications.{discord,slack}_webhook_url`
# for delivery to fire.
class AddWebhookFlagsToAppSettings < ActiveRecord::Migration[8.1]
  def change
    unless column_exists?(:app_settings, :discord_enabled)
      add_column :app_settings, :discord_enabled,
                 :boolean, null: false, default: false
    end

    unless column_exists?(:app_settings, :slack_enabled)
      add_column :app_settings, :slack_enabled,
                 :boolean, null: false, default: false
    end
  end
end
