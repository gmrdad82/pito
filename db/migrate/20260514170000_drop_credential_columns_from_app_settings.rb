# Phase 29 — Unit A1. AppSetting → credentials consolidation.
#
# Drops the seven secret-bearing / orphaned columns that drifted onto
# the de-facto-singleton `app_settings` row during alpha / beta-1:
#
#   * voyage_api_key        — SECRET. Moves back to
#                             `Rails.application.credentials.voyage`.
#   * youtube_api_key       — SECRET. Moves back to
#                             `Rails.application.credentials.google_oauth`.
#   * youtube_client_secret — SECRET. Same destination.
#   * youtube_client_id     — SECRET-adjacent. Same destination.
#   * youtube_redirect_uri  — deploy-time config. Same destination.
#   * slack_enabled         — orphaned dead gate column. The Slack /
#                             Discord delivery gate now derives from the
#                             `NotificationDeliveryChannel` row.
#   * discord_enabled       — orphaned dead gate column. Same.
#
# `remove_column` carries the original type / options so `down` is a
# clean recreate (plaintext on rollback — acceptable; rollback is a
# developer escape hatch and there is no production data).
class DropCredentialColumnsFromAppSettings < ActiveRecord::Migration[8.1]
  def change
    remove_column :app_settings, :voyage_api_key,        :text
    remove_column :app_settings, :youtube_api_key,       :text
    remove_column :app_settings, :youtube_client_id,     :text
    remove_column :app_settings, :youtube_client_secret, :text
    remove_column :app_settings, :youtube_redirect_uri,  :text
    remove_column :app_settings, :slack_enabled,   :boolean, default: false, null: false
    remove_column :app_settings, :discord_enabled, :boolean, default: false, null: false
  end
end
