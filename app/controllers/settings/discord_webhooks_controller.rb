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
class Settings::DiscordWebhooksController < ApplicationController
  TEST_PING_TEXT = "Pito test ping — Discord webhook configured."

  def update
    webhook_url = params[:discord_webhook_url].to_s.strip
    everything = coerce_boolean(:everything)
    daily_digest = coerce_boolean(:daily_digest)

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
      redirect_to settings_path, notice: "Discord webhook saved."
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
end
