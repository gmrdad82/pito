class AppSetting < ApplicationRecord
  encrypts :value, deterministic: true

  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :value, presence: true

  # Phase 15 §1 — Calendar Data Model. The install-level timezone seeds
  # `calendar_entries.timezone` on insert. Validate as a real IANA name.
  validate :timezone_must_be_iana

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    record
  end

  # Phase 29 — Unit A1. The Voyage API key moved back into
  # `Rails.application.credentials.voyage` (flat block — a single
  # `api_key` shared across environments). The "Voyage is configured"
  # gate checks the credentials presence instead of a dropped
  # `voyage_api_key` column — `Notes::EmbedJob` short-circuits when this
  # is false even if the per-target flag was somehow flipped true. The
  # non-secret `voyage_index_project_notes` flag STAYS on this table
  # (runtime-mutable from the Settings UI).
  def self.voyage_configured?
    Rails.application.credentials.dig(:voyage, :api_key).to_s.strip.present?
  end

  # Per-target flag: project-notes indexing. Returns false (not nil) when no
  # singleton exists so callers can use it directly in conditionals.
  def self.voyage_indexing_project_notes?
    first&.voyage_index_project_notes || false
  end

  # 2026-05-11 — master toggle for the global keyboard-navigation surface
  # (`keyboard_controller.js`). Returns `true` when no AppSetting row
  # exists yet so the install starts with the feature enabled (matches
  # the NOT NULL column default of `true`). Callers can use the
  # predicate directly in conditionals without nil-handling.
  def self.keyboard_navigation_enabled?
    row = first
    return true if row.nil?
    row.keyboard_navigation_enabled
  end

  # Writer counterpart used by SettingsController#update_appearance. The
  # AppSetting table is treated as de-facto singleton storage for these
  # column-backed flags; if no row exists yet we bootstrap one keyed on
  # `pane_title_length` (matches the Voyage update path's bootstrap
  # behaviour). Accepts a Boolean; the boundary conversion (yes/no →
  # Boolean) happens at the controller layer.
  def self.set_keyboard_navigation_enabled(value)
    row = first
    if row.nil?
      set("pane_title_length", ENV.fetch("PANE_TITLE_LENGTH", 14).to_s)
      row = first
    end
    row.update!(keyboard_navigation_enabled: value)
  end

  # Phase 29 — Unit A1 (Part 4 delivery bug fix). "Is Discord delivery
  # on" is derived entirely from the `NotificationDeliveryChannel` row
  # for the kind — its existence plus a present `webhook_url` and at
  # least one routing flag set (`everything` or `daily_digest`). The
  # orphaned `AppSetting.discord_enabled` boolean was never written by
  # the webhook controllers, so the old gate was always false and
  # Discord delivery was silently dead. The column is dropped; this
  # predicate is the new source of truth.
  def self.discord_delivery_enabled?
    delivery_channel_enabled?("discord")
  end

  # Phase 29 — Unit A1 (Part 4 delivery bug fix). Slack mirror of
  # `discord_delivery_enabled?` — derived from the
  # `NotificationDeliveryChannel` row for the kind, never the dropped
  # `slack_enabled` column.
  def self.slack_delivery_enabled?
    delivery_channel_enabled?("slack")
  end

  # True iff a `NotificationDeliveryChannel` row exists for the kind
  # with a present `webhook_url` and at least one routing flag
  # (`everything` or `daily_digest`) set. This is the single source of
  # truth for the "delivery is on" gate the dispatchers read.
  def self.delivery_channel_enabled?(kind)
    row = NotificationDeliveryChannel.find_record_for(kind)
    return false if row.nil?
    return false if row.webhook_url.to_s.strip.empty?

    row.everything? || row.daily_digest?
  end
  private_class_method :delivery_channel_enabled?

  private

  def timezone_must_be_iana
    return if timezone.blank?
    return if ActiveSupport::TimeZone[timezone].present?
    errors.add(:timezone, "is not a valid IANA timezone")
  end
end
