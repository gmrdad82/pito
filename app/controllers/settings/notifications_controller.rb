# Beta 4 — Phase F3-B. Unified notifications controller.
#
# Consolidates the prior `Settings::DiscordWebhooksController` and
# `Settings::SlackWebhooksController` into a single controller class.
# Each brand still ships an independent webhook URL form (one URL per
# brand, persisted as a `NotificationDeliveryChannel` row keyed on
# `kind`); the controller exposes two actions so the brand-specific
# tri-state save flow (blank → no-op, "clear" → clear, else →
# validate + test-ping + save) lives in its own method per brand
# without an `if brand == "..."` switch.
#
# Routes:
#   * `PATCH /settings/notifications/discord` → `#update_discord`
#   * `PATCH /settings/notifications/slack`   → `#update_slack`
#
# The save flow per brand mirrors the previous per-brand controllers
# byte-for-byte:
#
#   1. Strip the submitted URL. Blank → no-op (preserve existing).
#   2. Literal "clear" (case-insensitive) → clear the integration
#      (URL nil + both flags false) via the model's normalization
#      callback. No regex check, no test ping. Distinct
#      "<brand> cleared." flash.
#   3. Else → validate the URL shape with the brand's regex, fire a
#      test ping via `Webhooks::<Brand>Client#ping`, persist + stamp
#      `last_validated_at` only on a 2xx response.
#
# 2026-05-20 — F3-B-SIMPLIFY-MODEL. Per-brand routing flags are gone.
# The two shared toggles live on `AppSetting.singleton_row` and are
# updated through `Settings::NotificationTogglesController` (auto-save
# on change). This controller only manages the per-brand webhook URL.
class Settings::NotificationsController < ApplicationController
  CLEAR_KEYWORD = "clear"

  def update_discord
    webhook_url = params[:discord_webhook_url].to_s.strip

    if webhook_url.blank?
      redirect_to settings_path, notice: t("settings.discord.flash.unchanged")
      return
    end

    if webhook_url.casecmp(CLEAR_KEYWORD).zero?
      persist_cleared_discord
      return
    end

    unless NotificationDeliveryChannel::DISCORD_URL_REGEX.match?(webhook_url)
      redirect_to settings_path, alert: t("settings.discord.flash.invalid_url")
      return
    end

    ping_result = Pito::Notifications::Webhooks::DiscordClient.new(webhook_url).ping(t("settings.discord.test_ping_text"))

    unless ping_result.success?
      redirect_to settings_path,
                  alert: t("settings.discord.flash.ping_failed", error: ping_result.error)
      return
    end

    record = NotificationDeliveryChannel.find_or_initialize_by(kind: "discord")
    record.assign_attributes(
      webhook_url: webhook_url,
      last_validated_at: Time.current
    )

    if record.save
      redirect_to settings_path, notice: t("settings.discord.flash.updated")
    else
      redirect_to settings_path,
                  alert: t("settings.discord.flash.save_failed", errors: record.errors.full_messages.to_sentence)
    end
  end

  def update_slack
    webhook_url = params[:slack_webhook_url].to_s.strip

    if webhook_url.blank?
      redirect_to settings_path, notice: t("settings.slack.flash.unchanged")
      return
    end

    if webhook_url.casecmp(CLEAR_KEYWORD).zero?
      persist_cleared_slack
      return
    end

    unless NotificationDeliveryChannel::SLACK_URL_REGEX.match?(webhook_url)
      redirect_to settings_path, alert: t("settings.slack.flash.invalid_url")
      return
    end

    ping_result = Pito::Notifications::Webhooks::SlackClient.new(webhook_url).ping(t("settings.slack.test_ping_text"))

    unless ping_result.success?
      redirect_to settings_path,
                  alert: t("settings.slack.flash.ping_failed", error: ping_result.error)
      return
    end

    record = NotificationDeliveryChannel.find_or_initialize_by(kind: "slack")
    record.assign_attributes(
      webhook_url: webhook_url,
      last_validated_at: Time.current
    )

    if record.save
      redirect_to settings_path, notice: t("settings.slack.flash.updated")
    else
      redirect_to settings_path,
                  alert: t("settings.slack.flash.save_failed", errors: record.errors.full_messages.to_sentence)
    end
  end

  private

  # Persist the Discord row in its cleared state (URL nil). The per-brand
  # routing flags are gone (F3-B-SIMPLIFY-MODEL, 2026-05-20) — shared
  # toggles live on AppSetting and are NOT affected by clearing a webhook.
  # `last_validated_at` is intentionally left untouched so the operator
  # can still see the prior validation timestamp if they re-paste the
  # URL later.
  def persist_cleared_discord
    record = NotificationDeliveryChannel.find_or_initialize_by(kind: "discord")
    record.assign_attributes(webhook_url: nil)

    if record.save
      redirect_to settings_path, notice: t("settings.discord.flash.cleared")
    else
      redirect_to settings_path,
                  alert: t("settings.discord.flash.clear_failed", errors: record.errors.full_messages.to_sentence)
    end
  end

  def persist_cleared_slack
    record = NotificationDeliveryChannel.find_or_initialize_by(kind: "slack")
    record.assign_attributes(webhook_url: nil)

    if record.save
      redirect_to settings_path, notice: t("settings.slack.flash.cleared")
    else
      redirect_to settings_path,
                  alert: t("settings.slack.flash.clear_failed", errors: record.errors.full_messages.to_sentence)
    end
  end
end
