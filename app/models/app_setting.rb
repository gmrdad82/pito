class AppSetting < ApplicationRecord
  encrypts :value, deterministic: true

  # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — `voyage_api_key` lives on the
  # de-facto-singleton AppSetting row so the user can rotate it from the
  # Settings UI without a deploy. NOT deterministic — the key is sensitive,
  # never compared/queried, and benefits from probabilistic encryption.
  encrypts :voyage_api_key

  validates :key, presence: true, uniqueness: { case_sensitive: false }
  validates :value, presence: true

  # Phase 4 §3.5 (Phase B revamp) — when any per-target indexing flag is on,
  # the API key MUST be present. The validation triggers on both directions:
  # flipping a flag true while the key is blank, AND clearing the key while
  # any flag is true. Belt-and-suspenders on top of Notes::EmbedJob's own
  # dual check (model validation prevents the broken state at the form
  # boundary; the job re-checks at HTTP-call time in case of migration drift
  # or direct SQL writes).
  #
  # The validation method name uses the plural ("flags") so future indexing
  # targets (videos, channels, ...) can extend it without renaming.
  validate :voyage_target_flags_require_key

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

  # True iff the singleton has a non-blank Voyage API key. Treated as the
  # "Voyage is configured" gate — Notes::EmbedJob short-circuits when this
  # is false even if a per-target flag was somehow flipped true.
  def self.voyage_configured?
    first&.voyage_api_key.present?
  end

  # Per-target flag: project-notes indexing. Returns false (not nil) when no
  # singleton exists so callers can use it directly in conditionals.
  def self.voyage_indexing_project_notes?
    first&.voyage_index_project_notes || false
  end

  # Phase 16 §1 — Discord webhook delivery is enabled iff the master
  # toggle on the singleton is true AND the credentials carry a
  # non-blank `notifications.discord_webhook_url`. Returns false (not
  # nil) when no singleton exists or credentials are missing.
  def self.discord_delivery_enabled?
    return false unless first&.discord_enabled
    notifications_credentials_value(:discord_webhook_url).to_s.strip != ""
  end

  # Phase 16 §1 — Slack webhook delivery is enabled iff the master
  # toggle on the singleton is true AND the credentials carry a
  # non-blank `notifications.slack_webhook_url`.
  def self.slack_delivery_enabled?
    return false unless first&.slack_enabled
    notifications_credentials_value(:slack_webhook_url).to_s.strip != ""
  end

  # Read a key out of the optional `:notifications` credentials block.
  # Returns nil when the block (or the key) is missing.
  def self.notifications_credentials_value(key)
    Rails.application.credentials.dig(:notifications, key)
  end
  private_class_method :notifications_credentials_value

  private

  def voyage_target_flags_require_key
    return unless voyage_index_project_notes
    return if voyage_api_key.present?

    errors.add(:voyage_api_key,
               "Voyage API key required to enable project-notes indexing.")
  end

  def timezone_must_be_iana
    return if timezone.blank?
    return if ActiveSupport::TimeZone[timezone].present?
    errors.add(:timezone, "is not a valid IANA timezone")
  end
end
