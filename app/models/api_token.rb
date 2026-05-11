# Phase 3 — Step B (5b-token-and-auth-concern.md) — token model.
#
# Renamed from `McpAccessToken`. Adds user ownership, the scope array,
# and optional expiry. Digest semantics (HMAC-SHA256, secure compare)
# inherited from the prior model — but the pepper is now sourced from
# the `:tokens.pepper` credential rather than the global
# `secret_key_base`.
#
# Phase 8 — tenant drop (ADR 0003). The `tenant_id` column is gone.
# Tokens are owned by a User row install-wide.
#
# Validation rules:
#   - name presence
#   - token_digest presence + uniqueness
#   - last_token_preview presence
#   - scopes presence (empty array rejected) AND every entry in `Scopes::ALL`
#
# Class methods:
#   - `generate!(user:, name:, scopes:, expires_at: nil)` — returns
#     `[record, plaintext]`. Plaintext is shown once, never stored.
#   - `authenticate(plaintext)` — kept for the legacy lookup path used by
#     specs; the production lookup goes through `Api::TokenAuthenticator`.
#
# Instance methods:
#   - `revoked?` / `expired?` / `usable?`
#   - `touch_used!` — `update_columns(last_used_at: Time.current)`; skips
#     validations and callbacks so it's safe to call on every request.
class ApiToken < ApplicationRecord
  belongs_to :user

  validates :name, presence: true
  validates :token_digest, presence: true, uniqueness: true
  validates :last_token_preview, presence: true
  validates :scopes, presence: true
  validate  :scopes_subset_of_catalog
  validate  :dev_scope_only_when_exposed
  validate  :auth_scope_only_when_exposed

  scope :active, -> { where(revoked_at: nil) }
  scope :revoked, -> { where.not(revoked_at: nil) }

  # Generates a new token; stores the digest and the last-4 preview. Returns
  # the plaintext exactly once — callers must capture it now or lose it.
  def self.generate!(user:, name:, scopes:, expires_at: nil)
    plaintext = SecureRandom.urlsafe_base64(32)
    record = create!(
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

  # Resolve the HMAC pepper. Phase 12 Step A moved the resolution into
  # `Pito::TokenDigest.pepper` so the digest helper is shared by
  # `ApiToken` and `Session`. This wrapper is preserved for the legacy
  # callers (specs and the rake CRUD task) that referenced
  # `ApiToken.pepper` directly.
  def self.pepper
    Pito::TokenDigest.pepper
  end

  # HMAC-SHA256 digest with a server-side pepper. The pepper is required:
  # if it is unresolvable, `Pito::TokenDigest.call` raises
  # `Api::AuthConfigurationMissing` — preserving the original
  # loud-failure contract. `ApiToken.pepper` is passed through so
  # callers (including specs) can stub `ApiToken.pepper` to drive
  # the digest path.
  def self.digest(plaintext)
    Pito::TokenDigest.call(plaintext, pepper: pepper)
  end

  private

  def scopes_subset_of_catalog
    return if scopes.blank?

    invalid = Array(scopes) - Scopes::ALL
    return if invalid.empty?

    errors.add(:scopes, "contains invalid entries: #{invalid.join(", ")}")
  end

  # Phase 10 — strip-on-release (ADR 0004). Even if a `dev` scope row
  # would otherwise pass `scopes_subset_of_catalog`, reject when the
  # build has stripped `dev` from the catalog. The `Scopes::ALL`
  # constant is captured at boot, so it correctly reflects the
  # production posture; this guard adds a runtime check for tests that
  # stub the flag mid-process.
  def dev_scope_only_when_exposed
    return if Scopes.dev_exposed?
    return unless Array(scopes).include?(Scopes::DEV)

    errors.add(:scopes, "cannot include 'dev' in this build")
  end

  # Phase 25 — 01d. Mirror the dev-scope strip-on-release guard for the
  # `auth` scope. Production builds strip the scope; specs that stub the
  # flag mid-process see this runtime guard reject the row.
  def auth_scope_only_when_exposed
    return if Scopes.auth_exposed?
    return unless Array(scopes).include?(Scopes::AUTH)

    errors.add(:scopes, "cannot include 'auth' in this build")
  end
end
