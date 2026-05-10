# Phase 12 — Step A (6a-sessions-and-login-ui.md) — server-side session.
#
# One row per active browser/login. The cookie carries an opaque
# `plaintext` token; `token_digest` is `HMAC-SHA256(:tokens.pepper,
# plaintext)`. Server-side resolution looks up the row by digest, so a
# DB compromise never reveals usable cookie tokens directly.
#
# Lifetime semantics: revocation is the only end-state in v1. The cookie
# carries the expiration (session-only or 30 days when "remember me" is
# set). Periodic sweep of stale rows is a Phase 15 / observability
# concern; keep the row around for the audit trail until revoked.
#
# Phase 8 — tenant drop. The `tenant_id` column and `BelongsToTenant`
# default scope are gone; `Session.create_for!` is now a plain `create!`
# (no `unscoped` workaround required).
class Session < ApplicationRecord
  belongs_to :user

  validates :user_id, presence: true
  validates :token_digest, presence: true, uniqueness: true

  ACTIVITY_DEBOUNCE = 5.minutes
  REMEMBER_ME_TTL   = 30.days

  # Mints a new session row for `user`, returns `[record, plaintext]`.
  # Plaintext is shown once and goes into the signed cookie; `token_digest`
  # is what the database stores. Mirrors `ApiToken.generate!`.
  def self.create_for!(user:, ip: nil, user_agent: nil, remember: false)
    plaintext = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_digest: Pito::TokenDigest.call(plaintext),
      ip: ip,
      user_agent: user_agent,
      remember: remember ? true : false,
      last_activity_at: Time.current
    )
    [ record, plaintext ]
  end

  def revoked?
    revoked_at.present?
  end

  def current?
    Current.session.present? && id == Current.session.id
  end

  # Update `last_activity_at` only if it's been at least `ACTIVITY_DEBOUNCE`
  # since the last bump. Avoids one DB write per request. Uses
  # `update_columns` to skip validations / callbacks / `updated_at`.
  def touch_activity!
    return if last_activity_at.present? && last_activity_at >= ACTIVITY_DEBOUNCE.ago

    update_columns(last_activity_at: Time.current)
  end

  def revoke!
    update_columns(revoked_at: Time.current) unless revoked?
  end
end
