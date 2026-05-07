# Phase 3 — Step B (5b-token-and-auth-concern.md) — token model.
#
# Renamed from `McpAccessToken`. Adds tenant + user ownership, the scope
# array, and optional expiry. Digest semantics (HMAC-SHA256, secure compare)
# inherited from the prior model — but the pepper is now sourced from the
# `:tokens.pepper` credential rather than the global `secret_key_base`.
#
# Validation rules:
#   - name presence
#   - token_digest presence + uniqueness
#   - last_token_preview presence
#   - scopes presence (empty array rejected) AND every entry in `Scopes::ALL`
#
# Class methods:
#   - `generate!(tenant:, user:, name:, scopes:, expires_at: nil)` — returns
#     `[record, plaintext]`. Plaintext is shown once, never stored.
#   - `authenticate(plaintext)` — kept for the legacy lookup path used by
#     specs; the production lookup goes through `Api::TokenAuthenticator`.
#
# Instance methods:
#   - `revoked?` / `expired?` / `usable?`
#   - `touch_used!` — `update_columns(last_used_at: Time.current)`; skips
#     validations and callbacks so it's safe to call on every request.
class ApiToken < ApplicationRecord
  belongs_to :tenant
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :last_token_preview, presence: true
  validates :scopes, presence: true
  validate  :scopes_subset_of_catalog

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  # Generates a new token; stores the digest and the last-4 preview. Returns
  # the plaintext exactly once — callers must capture it now or lose it.
  def self.generate!(tenant:, user:, name:, scopes:, expires_at: nil)
    plaintext = SecureRandom.urlsafe_base64(32)
    record = create!(
      tenant: tenant,
      user: user,
      name: name,
      scopes: Array(scopes),
      expires_at: expires_at,
      token_digest: digest(plaintext),
      last_token_preview: plaintext.last(4)
    )
    [ record, plaintext ]
  end

  # Find an active, usable token by plaintext. Returns nil if not found,
  # revoked, or expired. Used by legacy specs and by the rake CRUD task; the
  # production HTTP path uses `Api::TokenAuthenticator` which surfaces the
  # specific failure reason for the audit log.
  def self.authenticate(plaintext)
    return nil if plaintext.blank?

    candidate_digest = digest(plaintext)
    token = active.find_by(token_digest: candidate_digest)
    return nil unless token
    return nil unless ActiveSupport::SecurityUtils.secure_compare(token.token_digest, candidate_digest)
    return nil unless token.usable?

    token.touch_used!
    token
  end

  def revoked?
    revoked_at.present?
  end

  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  def usable?
    !revoked? && !expired?
  end

  def revoke!
    update!(revoked_at: Time.current)
  end

  # Update last_used_at without firing validations or callbacks. Safe under
  # any default scope; no `updated_at` bump.
  def touch_used!
    update_columns(last_used_at: Time.current)
  end

  # Resolve the HMAC pepper. Three-tier fallback so CI (which has no
  # `config/master.key`) can still run the ApiToken specs while production
  # remains fail-fast:
  #
  #   1. `Rails.application.credentials.dig(:tokens, :pepper)` — canonical
  #      production source.
  #   2. `ENV["PITO_TOKENS_PEPPER"]` — escape hatch for environments that
  #      provision secrets via env (CI deploy preview, hosted runners that
  #      can't ship the master key).
  #   3. A fixed, well-known string — ONLY when `Rails.env.test?`. Lets
  #      the test suite compute deterministic digests without a master key.
  #
  # In production with no credential and no env var, this returns nil and
  # `digest` raises `Api::AuthConfigurationMissing` — preserving the
  # original loud-failure contract.
  def self.pepper
    Rails.application.credentials.dig(:tokens, :pepper) ||
      ENV["PITO_TOKENS_PEPPER"] ||
      (Rails.env.test? ? "test-pepper-not-a-secret" : nil)
  end

  # HMAC-SHA256 digest with a server-side pepper. The pepper is required:
  # if it is unresolvable (see `.pepper`), the auth concern raises a clear
  # error rather than silently digesting with `nil` (which would still be
  # deterministic but would make the database trivially auditable by anyone
  # who knows the algorithm).
  def self.digest(plaintext)
    pepper_value = pepper
    raise Api::AuthConfigurationMissing, "tokens.pepper credential is not set" if pepper_value.blank?

    OpenSSL::HMAC.hexdigest("SHA256", pepper_value, plaintext.to_s)
  end

  private

  def scopes_subset_of_catalog
    return if scopes.blank?

    invalid = Array(scopes) - Scopes::ALL
    return if invalid.empty?

    errors.add(:scopes, "contains invalid entries: #{invalid.join(", ")}")
  end
end
