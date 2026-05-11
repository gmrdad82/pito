class AppSetting < ApplicationRecord
  encrypts :value, deterministic: true

  # Phase 4 §3.5 (Phase B revamp, 2026-05-04) — `voyage_api_key` lives on the
  # de-facto-singleton AppSetting row so the user can rotate it from the
  # Settings UI without a deploy. NOT deterministic — the key is sensitive,
  # never compared/queried, and benefits from probabilistic encryption.
  encrypts :voyage_api_key

  # 2026-05-11 — YouTube OAuth + API credentials move out of
  # `Rails.application.credentials.google_oauth` into the singleton
  # row so the operator can rotate them from the Settings UI without
  # a deploy (same pattern as `voyage_api_key`). Sensitive fields
  # (`youtube_api_key`, `youtube_client_secret`) are encrypted via
  # Active Record Encryption; the OAuth client ID and the redirect
  # URI are public-ish (the client ID is exposed to any user who
  # completes an OAuth round-trip; the redirect URI is a public
  # callback URL) so they stay in plaintext for the UI to surface.
  #
  # The original `google_oauth` credentials block is deliberately
  # kept on disk as a one-line manual revert path — the runtime no
  # longer reads it (omniauth initializer + `Youtube::TokenRefresher`
  # + `Youtube::PublicClient` all read from AppSetting), but the
  # values stay populated in case the table gets wiped and a quick
  # revert is preferable to a fresh backfill. The
  # `pito:backfill_youtube_credentials` rake task seeds AppSetting
  # from the credentials block once; it is idempotent.
  encrypts :youtube_api_key
  encrypts :youtube_client_secret

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

  # 2026-05-11 — YouTube credentials accessors. All four return nil
  # when no singleton exists yet (greenfield install before any
  # backfill / form submit). Callers that need a non-nil default
  # apply their own fallback (e.g. the omniauth initializer falls
  # back to credentials + ENV; `youtube_redirect_uri_for_omniauth`
  # falls back to the production callback URL).
  def self.youtube_api_key
    first&.youtube_api_key
  end

  def self.youtube_client_id
    first&.youtube_client_id
  end

  def self.youtube_client_secret
    first&.youtube_client_secret
  end

  def self.youtube_redirect_uri
    first&.youtube_redirect_uri
  end

  # True iff every REQUIRED YouTube credential (api_key, client_id,
  # client_secret) is non-blank on the singleton row. Mirrors the
  # `voyage_configured?` predicate so callers can branch without
  # nil-handling. The redirect URI is NOT part of the required set
  # — omniauth falls back to a hard-coded default when it's blank.
  def self.youtube_configured?
    row = first
    return false if row.nil?
    row.youtube_api_key.to_s.strip.present? &&
      row.youtube_client_id.to_s.strip.present? &&
      row.youtube_client_secret.to_s.strip.present?
  end

  # Per-field configured predicates — used by the Settings view to
  # render `key configured (•••••••)` placeholders without leaking
  # the actual value.
  def self.youtube_api_key_configured?
    youtube_api_key.to_s.strip.present?
  end

  def self.youtube_client_id_configured?
    youtube_client_id.to_s.strip.present?
  end

  def self.youtube_client_secret_configured?
    youtube_client_secret.to_s.strip.present?
  end

  def self.youtube_redirect_uri_configured?
    youtube_redirect_uri.to_s.strip.present?
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
