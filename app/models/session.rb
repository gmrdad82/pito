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
#
# Phase 25 — 01b (LD-6). Pending-approval state machine.
#
# `state` enum (`active`, `pending_approval`, `expired`, `revoked`):
#
#   - `active` (default) — minted on a trusted-location login OR after a
#     pending row transitions on approve (01c) / 2FA success (01e).
#   - `pending_approval` — minted on a new-location correct-password
#     login when the user picked the "ask for approval" path.
#     `approval_required_until` is set 10 minutes in the future server-
#     side; the cron sweeper flips overdue rows to `expired`.
#   - `expired` — terminal. Set by `Auth::PendingSessionExpirer`. Cannot
#     transition back to `active` (Q-G option 2).
#   - `revoked` — terminal. Set by `revoke!` on user logout, session
#     revoke from `/settings/sessions`, or block action on a pending row.
class Session < ApplicationRecord
  belongs_to :user

  validates :user_id, presence: true
  validates :token_digest, presence: true, uniqueness: true

  ACTIVITY_DEBOUNCE = 5.minutes
  REMEMBER_ME_TTL   = 30.days

  # Phase 25 — 01b. Pending approval window. Sessions in
  # `pending_approval` MUST have `approval_required_until` set to
  # `PENDING_APPROVAL_TTL.from_now` at creation time; the cron sweeper
  # flips them to `expired` once the timestamp is in the past.
  PENDING_APPROVAL_TTL = 10.minutes

  enum :state, {
    active: 0,
    pending_approval: 1,
    expired: 2,
    revoked: 3
  }, prefix: :state

  # `pending` returns rows currently held for approval (regardless of
  # whether their window has elapsed); `expired_pending` is the subset
  # the sweeper transitions. `state_active` is the enum-generated scope
  # (state = active). `active_sessions` narrows further to non-revoked
  # rows; the project never carried a `Session.active` scope before
  # 01b, so this name avoids clashing with the auto-generated enum
  # predicate.
  scope :active_sessions,        -> { state_active.where(revoked_at: nil) }
  scope :pending,                -> { state_pending_approval }
  scope :expired_pending,        -> {
    state_pending_approval
      .where(arel_table[:approval_required_until].lt(Time.current))
  }
  scope :pending_within_window,  -> {
    state_pending_approval
      .where(arel_table[:approval_required_until].gt(Time.current))
  }

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

  # Phase 25 — 01b. Mint a session row in `pending_approval` state.
  # Returns `[record, plaintext]` for symmetry with `create_for!`. The
  # caller (`Auth::SessionPendingApprover`) redirects to
  # `/login/pending` and does NOT set the long-lived auth cookie — the
  # pending row carries the approval window, not active auth.
  def self.create_pending!(user:, ip: nil, user_agent: nil)
    plaintext = SecureRandom.urlsafe_base64(32)
    record = create!(
      user: user,
      token_digest: Pito::TokenDigest.call(plaintext),
      ip: ip,
      user_agent: user_agent,
      remember: false,
      last_activity_at: Time.current,
      state: :pending_approval,
      approval_required_until: PENDING_APPROVAL_TTL.from_now
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

  # Phase 25 — 01b. True iff this session is in `pending_approval` AND
  # its approval window has not yet elapsed. Used by the controller
  # gate on `/login/pending` and by the MCP `login_attempts_pending`
  # tool.
  def pending_within_window?
    state_pending_approval? && approval_required_until.present? &&
      approval_required_until > Time.current
  end

  # Phase 25 — 01b. True iff this session is `pending_approval` and the
  # window has elapsed. The cron sweeper calls
  # `Auth::PendingSessionExpirer.call` which uses the `expired_pending`
  # scope; this method is the per-row predicate for ad-hoc checks.
  def expired_pending?
    state_pending_approval? &&
      approval_required_until.present? &&
      approval_required_until <= Time.current
  end

  # Phase 25 — 01b. Flip an overdue pending row to `expired`. Idempotent:
  # already-expired or non-pending rows are no-ops. Returns truthy iff a
  # state change happened.
  def expire_if_overdue!
    return false unless expired_pending?
    update_columns(state: self.class.states[:expired])
  end

  # Phase 25 — 01b. Promote a `pending_approval` row to `active`. Raises
  # if the row is already terminal (`expired` or `revoked`) — only an
  # in-window pending row can be activated. Stamps `last_activity_at`
  # so the freshly-active session looks recent.
  def transition_to_active!
    if state_expired? || state_revoked?
      raise ActiveRecord::RecordInvalid.new(self),
            "cannot activate a #{state} session"
    end

    update!(
      state: :active,
      approval_required_until: nil,
      last_activity_at: Time.current
    )
  end
end
