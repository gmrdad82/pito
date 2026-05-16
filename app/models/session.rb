# Server-side session.
#
# One row per active browser/login. The cookie carries an opaque
# `plaintext` token; `token_digest` is `HMAC-SHA256(:tokens.pepper,
# plaintext)`. Server-side resolution looks up the row by digest, so a
# DB compromise never reveals usable cookie tokens directly.
#
# Lifetime semantics: revocation is the only end-state in v1. The
# cookie is session-only — the "remember me on this device (30 days)"
# checkbox + the `remember` column that drove it were dropped on
# 2026-05-16. Periodic sweep of stale rows is a Phase 15 / observability
# concern; keep the row around for the audit trail until revoked.
#
# Post-Phase-25 rollback. The `pending_approval` state + the
# `approval_required_until` window are gone — the new-location
# approval surface was removed entirely. Remaining states are
# `active`, `expired`, `revoked` (integer-backed; values preserved).
class Session < ApplicationRecord
  belongs_to :user

  validates :user_id, presence: true
  validates :token_digest, presence: true, uniqueness: true

  ACTIVITY_DEBOUNCE = 5.minutes

  # Rails 8.1 enum type inference can fail under autoload races /
  # bootsnap cache when the column type is integer and the enum
  # declaration is the hash-with-options positional form. An explicit
  # `attribute :state, :integer` locks the type ahead of the `enum`
  # call so `Undeclared attribute type for enum 'state'` cannot trip
  # under any boot-order interleaving.
  #
  # Value `1` (`pending_approval`) stayed reserved post-rollback — do
  # NOT renumber `expired`/`revoked` even though `1` is unused; the
  # production database carries integer values, and renumbering would
  # silently relabel existing rows.
  attribute :state, :integer
  enum :state, {
    active: 0,
    expired: 2,
    revoked: 3
  }, prefix: :state

  # `state_active` is the enum-generated scope (state = active).
  # `active_sessions` narrows further to non-revoked rows.
  scope :active_sessions, -> { state_active.where(revoked_at: nil) }

  # Mints a new session row for `user`, returns `[record, plaintext]`.
  # Plaintext is shown once and goes into the signed cookie; `token_digest`
  # is what the database stores. Mirrors `ApiToken.generate!`.
  def self.create_for!(user:, ip: nil, user_agent: nil)
    plaintext = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_digest: Pito::TokenDigest.call(plaintext),
      ip: ip,
      user_agent: user_agent,
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
    return if revoked?
    update_columns(revoked_at: Time.current, state: self.class.states[:revoked])
  end
end
