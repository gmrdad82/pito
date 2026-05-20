# Beta 4 — Phase F3-B (2026-05-20 SIMPLIFY-MODEL). Shared notification
# routing toggles.
#
# Two URL combinations:
#
#   PATCH /settings/notification_toggles/all
#   PATCH /settings/notification_toggles/daily_digest
#
# Body: `enabled=yes` or `enabled=no` per the yes/no boundary rule.
#
# The unified notifications panel renders ONE shared toggles block at
# the top. Each toggle now flips a SHARED column on the canonical
# `AppSetting` singleton row — NOT a per-brand routing flag. The
# `:kind` segment maps to the column on `app_settings`:
#
#   "all"          -> `notifications_send_all`
#   "daily_digest" -> `notifications_send_daily_digest`
#
# Per the SIMPLIFY-MODEL lock-in:
#   * Checkboxes save independently of webhook state. The toggle can
#     be ON even when no webhook is configured (no validator blocks
#     it). The notification worker silently skips per brand if no
#     webhook is configured.
#   * `flags_require_webhook_url` is gone from the model.
#   * The brand-specific webhook URL update flow stays untouched.
#
# Response: redirect back to /settings with a notice naming the new
# state. Turbo follows the redirect, the page reloads, and the flash
# toast surfaces in the layout-level region.
class Settings::NotificationTogglesController < ApplicationController
  # Maps the URL segment to the column on `app_settings`.
  KINDS = {
    "all"          => :notifications_send_all,
    "daily_digest" => :notifications_send_daily_digest
  }.freeze

  # Maps the column symbol back to the human-readable label used in the
  # success flash. Mirrors the i18n key shape used by the prior
  # implementation so the flashes copy stays unchanged.
  LABEL_KEYS = {
    notifications_send_all:          "all",
    notifications_send_daily_digest: "daily_digest"
  }.freeze

  def update
    kind = params[:kind].to_s
    column = KINDS[kind]

    unless column
      redirect_to settings_path, alert: t("settings.notification_toggle.flash.unknown")
      return
    end

    enabled = coerce_boolean(:enabled)

    AppSetting.set_notification_toggle!(column, enabled)

    redirect_to settings_path,
                notice: t(
                  "settings.notification_toggle.flash.toggled",
                  kind: t("settings.notification_toggle.kind.#{LABEL_KEYS.fetch(column)}"),
                  state: enabled ? "on" : "off"
                )
  end

  private

  def coerce_boolean(key)
    raw = params[key].to_s
    YesNo.yes_no?(raw) && YesNo.from_yes_no(raw)
  end
end
