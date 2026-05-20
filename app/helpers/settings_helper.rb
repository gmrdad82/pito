# 2026-05-17 webhook URL hardening helpers.
#
# Helpers for the /settings panes. Today's only inhabitant is
# `webhook_url_mask` — the canonical source for the placeholder mask
# that the Discord + Slack webhook URL inputs render in place of the
# real (encrypted at rest) URL value. Centralising the mask string
# here means no view template ever inlines a brand-specific prefix
# string; any future tweak (different mask glyph, different prefix
# trim, additional provider) lands in one place.
module SettingsHelper
  # Renders a placeholder mask string for a webhook URL field. Used as
  # the input's `placeholder=""` attribute when the URL is set — the
  # actual URL value is NEVER rendered in HTML view source (only the
  # mask is visible). The brand-specific prefix is the publicly-known
  # portion (Discord and Slack webhook URLs all share the same prefix);
  # the secret portion shows as three asterisks `***`.
  #
  # The webhook URL itself stays encrypted at rest (Active Record
  # Encryption on `NotificationDeliveryChannel#webhook_url`) and the
  # `:webhook_url` parameter is filtered in
  # `config/initializers/filter_parameter_logging.rb` so logs never
  # capture the value either. The mask is the third leg of the
  # secrets-in-DOM defense.
  #
  # @param brand [Symbol] :discord or :slack
  # @return [String] e.g. "https://discord.com/***"
  def webhook_url_mask(brand)
    case brand
    when :discord then "https://discord.com/***"
    when :slack   then "https://hooks.slack.com/***"
    else raise ArgumentError, "unknown brand: #{brand.inspect}"
    end
  end

  # Beta 4 — F3-B-SIMPLIFY-MODEL (2026-05-20). Renders the unified-
  # notifications shared toggle state for the given column.
  #
  # The two shared columns live on the canonical
  # `AppSetting.singleton_row`. The view passes either `:all` or
  # `:daily_digest`; the helper maps to the matching column predicate.
  # Checkboxes are now independent of webhook configuration — the
  # toggle can be ON even when no webhook URL is set.
  #
  # @param toggle [Symbol] :all or :daily_digest
  # @return [Boolean]
  def shared_routing_flag_on?(toggle)
    case toggle.to_sym
    when :all, :everything             then AppSetting.notifications_send_all?
    when :daily_digest                 then AppSetting.notifications_send_daily_digest?
    else
      false
    end
  end
end
