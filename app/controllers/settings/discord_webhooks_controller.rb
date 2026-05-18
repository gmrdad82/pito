# Phase 26 — 01c. Discord webhook pane controller.
#
# Mirror of `Settings::SlackWebhooksController`. Single `update`
# endpoint behind the Settings Discord pane URL form. The form submits
# only the URL field — the 2 routing flags (`everything`,
# `daily_digest`) moved to per-flag auto-save toggles handled by
# `Settings::NotificationTogglesController` on 2026-05-17.
#
# Save flow (per locked decisions in the spec dispatch):
#
#   1. Validate the URL shape with the regex. Fail fast (no test ping)
#      if it does not match — flash an error and redirect back.
#   2. Send a test ping via `Webhooks::DiscordClient#ping`. If the ping
#      fails (non-2xx, timeout, DNS, TLS), do NOT persist the row —
#      flash an error explaining the specific failure.
#   3. Only on a 2xx test ping do we upsert the
#      `notification_delivery_channels` row keyed on `kind: "discord"`
#      and stamp `last_validated_at`.
#
# 2026-05-16 — recent-TOTP gate dropped from this surface. The only
# /settings write that still pops the TOTP-code modal is the profile
# pane (`Settings::UserController#update`). Webhook saves are plain
# saves now.
#
# 2026-05-17 webhook URL hardening — input value masking.
#
# The Discord pane no longer renders the real webhook URL in the
# input's `value=""`. The field always submits empty unless the
# operator types something new. The controller's update flow is now
# tri-state:
#
#   * BLANK         → no-op (preserve the existing URL). The masked
#                     input always posts blank when untouched; we
#                     MUST NOT clear on blank or every page-level
#                     save (the now-removed routing-flag form) would
#                     have wiped the URL. The 2 routing checkboxes
#                     moved to `Settings::NotificationTogglesController`
#                     so this controller only owns the URL surface.
#   * "clear"       → clear the integration (URL nil + flags false).
#                     The literal word "clear" is the cooperating
#                     gesture; the hint copy beneath the input names
#                     it explicitly.
#   * else          → treat as a new URL, run the regex + test-ping
#                     validation flow, persist on success.
class Settings::DiscordWebhooksController < ApplicationController
  CLEAR_KEYWORD = "clear"

  def update
    webhook_url = params[:discord_webhook_url].to_s.strip

    if webhook_url.blank?
      # Masked input → empty submission on every page-level save
      # would otherwise wipe the URL. Treat blank as "leave alone".
      redirect_to settings_path, notice: t("settings.discord.flash.unchanged")
      return
    end

    if webhook_url.casecmp(CLEAR_KEYWORD).zero?
      persist_cleared_record
      return
    end

    unless NotificationDeliveryChannel::DISCORD_URL_REGEX.match?(webhook_url)
      redirect_to settings_path, alert: t("settings.discord.flash.invalid_url")
      return
    end

    ping_result = Webhooks::DiscordClient.new(webhook_url).ping(t("settings.discord.test_ping_text"))

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

  private

  # Persist the row in its cleared state (URL nil + both flags false).
  # The model's `before_validation` callback handles the actual
  # nilify + zero pass — we just have to assign the blank URL through
  # and save. `last_validated_at` is intentionally left untouched so
  # the operator can still see "last validated at …" on the prior
  # configuration if they re-paste the URL later.
  def persist_cleared_record
    record = NotificationDeliveryChannel.find_or_initialize_by(kind: "discord")
    record.assign_attributes(webhook_url: nil, everything: false, daily_digest: false)

    if record.save
      redirect_to settings_path, notice: t("settings.discord.flash.cleared")
    else
      redirect_to settings_path,
                  alert: t("settings.discord.flash.clear_failed", errors: record.errors.full_messages.to_sentence)
    end
  end
end
