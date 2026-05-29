# frozen_string_literal: true

# Install-wide settings.
#
# Two row shapes share this table:
#   1. Key/value rows — anything addressable by string key.
#   2. The singleton row (`key = "__singleton__"`) — carries TOTP state
#      and pre-allocated encrypted API key columns. All class-level
#      helpers route through `singleton_row`.
#
# API-key reads fall through to `Rails.application.credentials` when
# the singleton row column is blank. Lets keys move out of credentials
# gradually without a forced migration.
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

  def self.totp_enabled?
    row = singleton_row
    row.totp_enabled_at.present? && row.totp_disabled_at.nil?
  end

  def self.enroll_totp!(seed:)
    singleton_row.update!(
      totp_seed_encrypted: seed,
      totp_enabled_at: Time.current,
      totp_disabled_at: nil,
      totp_last_used_step: nil
    )
  end

  def self.disable_totp!
    singleton_row.update!(
      totp_seed_encrypted: nil,
      totp_enabled_at: nil,
      totp_disabled_at: Time.current,
      totp_last_used_step: nil
    )
  end

  def self.totp_seed
    singleton_row.totp_seed_encrypted
  end

  # ── API keys (fall through to credentials when blank) ────────────────

  def self.google_oauth_client_id
    singleton_row.google_oauth_client_id.presence ||
      Rails.application.credentials.dig(:google, :client_id)
  end

  def self.google_oauth_client_secret
    singleton_row.google_oauth_client_secret.presence ||
      Rails.application.credentials.dig(:google, :client_secret)
  end

  def self.voyage_api_key
    singleton_row.voyage_api_key.presence ||
      Rails.application.credentials.dig(:voyage, :api_key)
  end
end
