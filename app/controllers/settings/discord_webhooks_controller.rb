# Phase 26 — 01c. Discord webhook pane controller.
#
# Mirror of `Settings::SlackWebhooksController`. Single `update`
# endpoint behind the Settings Discord pane form. The form submits
# three fields:
#
#   * `webhook_url` — the Discord webhook URL (must match the regex
#     on `NotificationDeliveryChannel::DISCORD_URL_REGEX`, accepting
#     both `discord.com` and `discordapp.com` host forms).
#   * `everything` — `"yes"` / `"no"` Boolean routing flag.
#   * `daily_digest` — `"yes"` / `"no"` Boolean routing flag.
#
# Save flow (per locked decisions in the spec dispatch):
#
#   1. Validate the URL shape with the regex. Fail fast (no test ping)
#      if it does not match — flash an error and redirect back.
#   2. Send a test ping via `Webhooks::DiscordClient#ping`. If the ping
#      fails (non-2xx, timeout, DNS, TLS), do NOT persist the row —
#      flash an error explaining the specific failure.
#   3. Only on a 2xx test ping do we upsert the
#      `notification_delivery_channels` row keyed on `kind: "discord"`,
#      stamp `last_validated_at`, persist `everything` + `daily_digest`,
#      and flash success.
#
# Per CLAUDE.md hard rule, the booleans cross the wire as
# `"yes"` / `"no"` strings and convert to Boolean at the controller
# boundary via `YesNo.from_yes_no`. The model column stays Boolean.
#
# 2026-05-16 — recent-TOTP gate dropped from this surface. The only
# /settings write that still pops the TOTP-code modal is the profile
# pane (`Settings::UserController#update`). Webhook saves are plain
# saves now.
#
# 2026-05-16 webhook-clear UX tweak.
# A blank `discord_webhook_url` is the "clear the integration" gesture
# — the controller skips the URL-regex check + test ping and persists
# the row with `webhook_url = nil` + both routing flags reset. The
# model's `before_validation` callback enforces the same invariant for
# any other surface (MCP, console, future CLI) so the controller's job
# is just to assign attributes, save, and pick the right flash copy.
class Settings::DiscordWebhooksController < ApplicationController
  TEST_PING_TEXT = "Pito test ping — Discord webhook configured."

  def update
    webhook_url = params[:discord_webhook_url].to_s.strip
    everything = coerce_boolean(:everything)
    daily_digest = coerce_boolean(:daily_digest)

    if webhook_url.blank?
      persist_cleared_record
      return
    end

    unless NotificationDeliveryChannel::DISCORD_URL_REGEX.match?(webhook_url)
      redirect_to settings_path, alert: "invalid Discord webhook URL."
      return
    end

    ping_result = Webhooks::DiscordClient.new(webhook_url).ping(TEST_PING_TEXT)

    unless ping_result.success?
      redirect_to settings_path,
                  alert: "Discord test ping failed: #{ping_result.error}."
      return
    end

    record = NotificationDeliveryChannel.find_or_initialize_by(kind: "discord")
    record.assign_attributes(
      webhook_url: webhook_url,
      everything: everything,
      daily_digest: daily_digest,
      last_validated_at: Time.current
    )

    if record.save
      redirect_to settings_path, notice: "Discord webhook updated."
    else
      redirect_to settings_path,
                  alert: "could not save Discord webhook: #{record.errors.full_messages.to_sentence}."
    end
  end

  private

  # `params[key]` is the wire form (`"yes"` / `"no"`). Anything else is
  # a malformed request — default to false (the same posture as the
  # other settings panes that use yes/no radios).
  def coerce_boolean(key)
    raw = params[key].to_s
    YesNo.yes_no?(raw) && YesNo.from_yes_no(raw)
  end

  # 2026-05-16 webhook-clear UX tweak.
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
      redirect_to settings_path, notice: "Discord webhook cleared."
    else
      redirect_to settings_path,
                  alert: "could not clear Discord webhook: #{record.errors.full_messages.to_sentence}."
    end
  end
end
