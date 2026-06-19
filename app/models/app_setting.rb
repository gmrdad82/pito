# frozen_string_literal: true

# Install-wide settings.
#
# Two row shapes share this table:
#   1. Key/value rows — anything addressable by string key.
#   2. The singleton row (`key = "__singleton__"`) — carries TOTP state
#      and pre-allocated encrypted API key columns. All class-level
#      helpers route through `singleton_row`.
#
# API-key reads fall through to ENV vars when the singleton row column
# is blank. Lets keys be supplied via the environment without a forced
# DB write.
class AppSetting < ApplicationRecord
  SINGLETON_KEY = "__singleton__"

  encrypts :value, deterministic: true
  encrypts :totp_seed_encrypted
  encrypts :google_oauth_client_id
  encrypts :google_oauth_client_secret
  encrypts :voyage_api_key

  validates :key,
            uniqueness: { case_sensitive: false },
            allow_nil: true

  def self.get(key)
    find_by(key: key)&.value
  end

  def self.set(key, value)
    record = find_or_initialize_by(key: key)
    record.update!(value: value)
    record
  end

  def self.singleton_row
    row = find_by(key: SINGLETON_KEY)
    return row if row

    create!(key: SINGLETON_KEY)
  rescue ActiveRecord::RecordNotUnique
    find_by!(key: SINGLETON_KEY)
  end

  # ── TOTP ─────────────────────────────────────────────────────────────

  def self.enroll_totp!(seed:)
    singleton_row.update!(
      totp_seed_encrypted: seed,
      totp_last_used_step: nil
    )
  end

  def self.totp_seed
    singleton_row.totp_seed_encrypted
  end

  after_save { Pito::Credentials.invalidate! }

  # ── API keys ───────────────────────────────────────────────────────

  def self.google_oauth_client_id
    singleton_row.google_oauth_client_id
  end

  def self.google_oauth_client_secret
    singleton_row.google_oauth_client_secret
  end

  # Fields stored as plain key/value rows — value column is encrypted
  # (deterministic). Avoids schema migrations for per-service credentials.
  GOOGLE_OAUTH_REDIRECT_URI_KEY = "google_oauth_redirect_uri"
  GOOGLE_API_KEY_KEY            = "google_api_key"
  IGDB_CLIENT_ID_KEY            = "igdb_client_id"
  IGDB_CLIENT_SECRET_KEY        = "igdb_client_secret"
  SLACK_WEBHOOK_URL_KEY         = "slack_webhook_url"
  DISCORD_WEBHOOK_URL_KEY       = "discord_webhook_url"

  def self.google_oauth_redirect_uri
    get(GOOGLE_OAUTH_REDIRECT_URI_KEY)
  end

  def self.google_oauth_redirect_uri=(uri)
    set(GOOGLE_OAUTH_REDIRECT_URI_KEY, uri)
  end

  def self.google_api_key
    get(GOOGLE_API_KEY_KEY)
  end

  def self.google_api_key=(key)
    set(GOOGLE_API_KEY_KEY, key)
  end

  def self.igdb_client_id
    get(IGDB_CLIENT_ID_KEY)
  end

  def self.igdb_client_id=(id)
    set(IGDB_CLIENT_ID_KEY, id)
  end

  def self.igdb_client_secret
    get(IGDB_CLIENT_SECRET_KEY)
  end

  def self.igdb_client_secret=(secret)
    set(IGDB_CLIENT_SECRET_KEY, secret)
  end

  def self.slack_webhook_url
    get(SLACK_WEBHOOK_URL_KEY)
  end

  def self.slack_webhook_url=(url)
    set(SLACK_WEBHOOK_URL_KEY, url)
  end

  def self.discord_webhook_url
    get(DISCORD_WEBHOOK_URL_KEY)
  end

  def self.discord_webhook_url=(url)
    set(DISCORD_WEBHOOK_URL_KEY, url)
  end

  def self.voyage_api_key
    singleton_row.voyage_api_key
  end

  # True when a Voyage API key is configured — gates every Voyage embedding call
  # (Game/Channel VoyageIndexer, Voyage::Stats).
  def self.voyage_configured?
    voyage_api_key.present?
  end

  # ── Sound / FX toggles ────────────────────────────────────────────────
  #
  # Stored as plain key/value rows ("sound_enabled", "fx_enabled").
  # Default is true — the flag is only false when the stored value is
  # explicitly "false".

  SOUND_ENABLED_KEY = "sound_enabled"
  FX_ENABLED_KEY    = "fx_enabled"

  def self.sound_enabled?
    get(SOUND_ENABLED_KEY) != "false"
  end

  def self.sound_enabled=(bool)
    set(SOUND_ENABLED_KEY, bool.to_s)
  end

  def self.fx_enabled?
    get(FX_ENABLED_KEY) != "false"
  end

  def self.fx_enabled=(bool)
    set(FX_ENABLED_KEY, bool.to_s)
  end

  # ── Theme ─────────────────────────────────────────────────────────────────
  #
  # Stored as a plain key/value row ("theme").
  # Default is "tokyo-night" — returned whenever no row has been stored yet.

  THEME_KEY         = "theme"
  THEME_DEFAULT     = "tokyo-night"

  def self.theme
    get(THEME_KEY).presence || THEME_DEFAULT
  end

  def self.theme=(slug)
    set(THEME_KEY, slug.to_s)
  end

  # ── Time zone ──────────────────────────────────────────────────────────────
  #
  # Stored as a plain key/value row ("timezone") holding an IANA identifier
  # (e.g. "Europe/Madrid"). Default is "UTC". ActiveRecord keeps storing UTC
  # internally — this setting only governs how times are rendered and how
  # schedule input is interpreted (see ApplicationController#set_user_time_zone).

  TIMEZONE_KEY     = "timezone"
  TIMEZONE_DEFAULT = "UTC"

  def self.timezone
    get(TIMEZONE_KEY).presence || TIMEZONE_DEFAULT
  end

  # Validates that +value+ names a real zone (friendly name or IANA identifier)
  # before persisting, and normalizes it to its IANA identifier. Raises
  # ArgumentError for anything ActiveSupport::TimeZone cannot resolve.
  def self.timezone=(value)
    zone = ActiveSupport::TimeZone[value.to_s]
    raise ArgumentError, "invalid time zone: #{value.inspect}" unless zone

    set(TIMEZONE_KEY, zone.tzinfo.identifier)
  end
end
