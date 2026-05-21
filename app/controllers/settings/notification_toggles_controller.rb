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
# Response: `head :no_content` (HTTP 204). FB-147 (2026-05-21) — the
# previous `redirect_to settings_path` triggered Turbo Drive to swap
# the entire page on every checkbox toggle, blowing away cursor
# focus + scroll position + in-flight INSERT mode. The toggle's
# visual feedback (the [x] glyph + the braille spinner during save)
# is owned client-side by `tui-toggle-feedback`; the success flash
# was redundant for an auto-saved row. Returning 204 keeps Turbo
# happy (no navigation, no body swap) while the auto-submit
# controller fires-and-forgets.
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

    # FB-147 (2026-05-21) — fire-and-forget. The checkbox glyph + the
    # braille spinner are owned by `tui-toggle-feedback`; the auto-save
    # row needs zero feedback from the server beyond a 2xx that ends
    # the spinner. Returning a redirect (the prior implementation)
    # caused Turbo Drive to swap the entire body — wiping cursor
    # focus + scroll + INSERT mode mid-toggle.
    head :no_content
  end

  private

  def coerce_boolean(key)
    raw = params[key].to_s
    YesNo.yes_no?(raw) && YesNo.from_yes_no(raw)
  end
end
