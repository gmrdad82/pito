# 2026-05-17 — auto-save endpoint for the 4 notification routing flags.
#
# One controller, one action, four URL combinations:
#
#   PATCH /settings/notification_toggles/discord/everything
#   PATCH /settings/notification_toggles/discord/daily_digest
#   PATCH /settings/notification_toggles/slack/everything
#   PATCH /settings/notification_toggles/slack/daily_digest
#
# `:brand` is `discord` or `slack` (the `NotificationDeliveryChannel.kind`
# value). `:kind` is the column to toggle on the row — `everything` or
# `daily_digest`. The router constraint enforces both allowlists; the
# controller reapplies them as defense-in-depth.
#
# Body: `enabled=yes` or `enabled=no` per the yes/no boundary rule. The
# value is coerced via `YesNo` (same posture as the brand-pane
# `coerce_boolean` private helpers — anything malformed defaults to
# false).
#
# Persistence:
#   * The row is found/initialized on `kind:` (the unique index on
#     `kind` enforces install-singleton-per-provider).
#   * The matching boolean column is assigned.
#   * Save runs the model's `flags_require_webhook_url` validator —
#     turning a flag ON without a webhook URL fails with a flash
#     alert and reverts the checkbox visually on next page load.
#
# Response: redirect back to /settings with a notice naming the new
# state (e.g. "Discord every notification on" / "Slack daily digest
# off"). Turbo follows the redirect, the page reloads, and the flash
# toast surfaces in the layout-level region. Auto-dismiss is handled
# by `toast_controller.js`.
class Settings::NotificationTogglesController < ApplicationController
  BRANDS = %w[discord slack].freeze
  KINDS = %w[everything daily_digest].freeze

  def update
    brand = params[:brand].to_s
    kind = params[:kind].to_s

    unless BRANDS.include?(brand) && KINDS.include?(kind)
      redirect_to settings_path, alert: t("settings.notification_toggle.flash.unknown")
      return
    end

    enabled = coerce_boolean(:enabled)

    record = NotificationDeliveryChannel.find_or_initialize_by(kind: brand)
    record.assign_attributes(kind => enabled)

    if record.save
      redirect_to settings_path,
                  notice: t(
                    "settings.notification_toggle.flash.toggled",
                    brand: t("settings.notification_toggle.brand.#{brand}"),
                    kind: t("settings.notification_toggle.kind.#{kind}"),
                    state: enabled ? "on" : "off"
                  )
    else
      # The most common failure here is the
      # `flags_require_webhook_url` validator — flipping a flag on
      # before the URL is configured. The model's `:base` error already
      # reads as a complete sentence ("Slack webhook URL not
      # configured."), so surface it verbatim instead of wrapping it
      # in a "could not toggle X: Y" prefix that doubles up the brand
      # name.
      #
      # `redirect_to` (302) + Turbo follow re-renders /settings with the
      # checkbox reflecting the actual persisted state (the save
      # rolled back), so the visual reverts automatically.
      redirect_to settings_path,
                  alert: record.errors.full_messages.to_sentence.presence ||
                         t(
                           "settings.notification_toggle.flash.toggle_failed",
                           brand: t("settings.notification_toggle.brand.#{brand}"),
                           kind: t("settings.notification_toggle.kind.#{kind}")
                         )
    end
  end

  private

  def coerce_boolean(key)
    raw = params[key].to_s
    YesNo.yes_no?(raw) && YesNo.from_yes_no(raw)
  end
end
