# Phase 26 — 01b. Slack webhook pane controller.
#
# Single `update` endpoint behind the Settings Slack pane form. The
# form submits three fields:
#
#   * `webhook_url` — the Slack incoming-webhook URL (must match the
#     regex on `NotificationDeliveryChannel::SLACK_URL_REGEX`).
#   * `everything` — `"yes"` / `"no"` Boolean routing flag.
#   * `daily_digest` — `"yes"` / `"no"` Boolean routing flag.
#
# Save flow (per locked decisions in the spec dispatch):
#
#   1. Validate the URL shape with the regex. Fail fast (no test ping)
#      if it does not match — flash an error and redirect back.
#   2. Send a test ping via `Webhooks::SlackClient#ping`. If the ping
#      fails (non-2xx, timeout, DNS, TLS), do NOT persist the row —
#      flash an error explaining the specific failure.
#   3. Only on a 2xx test ping do we upsert the
#      `notification_delivery_channels` row keyed on `kind: "slack"`,
#      stamp `last_validated_at`, persist `everything` + `daily_digest`,
#      and flash success.
#
# Per CLAUDE.md hard rule, the booleans cross the wire as
# `"yes"` / `"no"` strings and convert to Boolean at the controller
# boundary via `YesNo.from_yes_no`. The model column stays Boolean.
class Settings::SlackWebhooksController < ApplicationController
  include RecentTotpVerification

  TEST_PING_TEXT = "Pito test ping — Slack webhook configured."

  def update
    # 2026-05-11 — gate Slack webhook writes behind a fresh TOTP
    # verification when 2FA is on. Replacing the URL ships pito's
    # notification stream to an external endpoint, so we treat it
    # as a sensitive write.
    return unless require_recent_totp_if_enabled!(redirect_on_failure: settings_path)

    webhook_url = params[:slack_webhook_url].to_s.strip
    everything = coerce_boolean(:everything)
    daily_digest = coerce_boolean(:daily_digest)

    unless NotificationDeliveryChannel::SLACK_URL_REGEX.match?(webhook_url)
      redirect_to settings_path, alert: "invalid Slack webhook URL."
      return
    end

    ping_result = Webhooks::SlackClient.new(webhook_url).ping(TEST_PING_TEXT)

    unless ping_result.success?
      redirect_to settings_path,
                  alert: "Slack test ping failed: #{ping_result.error}."
      return
    end

    record = NotificationDeliveryChannel.find_or_initialize_by(kind: "slack")
    record.assign_attributes(
      webhook_url: webhook_url,
      everything: everything,
      daily_digest: daily_digest,
      last_validated_at: Time.current
    )

    if record.save
      redirect_to settings_path, notice: "Slack webhook saved."
    else
      redirect_to settings_path,
                  alert: "could not save Slack webhook: #{record.errors.full_messages.to_sentence}."
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
