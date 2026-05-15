# Phase 29 — Unit A2. Reset-password-via-2FA — the only self-service
# browser recovery path.
#
# pito does not run SMTP, so there is no email-based password
# recovery. With `email` dropped entirely (this unit), the recovery
# story is rebuilt around the second factor the user already has: a
# user proves possession of their TOTP authenticator (a live 6-digit
# code) OR a backup code (single-use, consumed), and on that proof is
# allowed to set a new password.
#
# Threat posture — mirrors `SessionsController` exactly:
#
#   - No account-existence oracle. Unknown username,
#     known-username-without-TOTP, and wrong-code all produce the
#     identical generic `reset failed.` response and the identical
#     wall-clock cost (the unknown-username branch pays the same
#     constant-time dummy bcrypt compare `SessionsController` uses).
#   - Throttled in `rack_attack.rb` (per-IP + per-username).
#   - The reset marker is a signed cookie + a `Rails.cache` nonce,
#     same pattern and TTL as `SessionsController::PRE_AUTH_COOKIE`.
#     The nonce is consumed on a successful `update` so the marker
#     cannot be replayed.
#   - A successful reset revokes EVERY `Session` row for the user (a
#     captured cookie cannot survive a reset) and does NOT auto-log
#     the user in — they re-authenticate fresh through `/login`,
#     which for a TOTP-configured user also re-runs the TOTP login
#     challenge.
#
# Lockout consequence: a user who loses BOTH their authenticator
# device AND every backup code has no self-service browser recovery —
# by design. The operator escape hatch is the
# `bin/rails pito:user:reset_totp[username]` rake task.
class PasswordResetsController < ApplicationController
  # Phase 29 — Unit A2 follow-up — security finding F6. Shared
  # constant-ish-time bcrypt compare used by the bail branches
  # (unknown username, no-TOTP) AND — per F2 — by the wrong-code
  # branch, so all three failure paths bottom out through the same
  # wall-clock cost. Previously the method body was duplicated here
  # and in `SessionsController`. See
  # `app/controllers/concerns/sessions/bcrypt_dummy_compare.rb`.
  include Sessions::BcryptDummyCompare

  allow_anonymous :new, :create, :edit, :update

  # Signed cookie carrying the short-lived reset marker minted after a
  # successful username + code verification. Payload: user_id + a
  # `Rails.cache` nonce. Same nonce-mirror pattern as the pre-auth
  # marker — the nonce is consumed on a successful password set.
  RESET_COOKIE    = :pito_password_reset
  RESET_TTL       = 10.minutes
  NONCE_CACHE_KEY = "password_reset_nonce:".freeze

  def self.reset_nonce_cache_key(user_id)
    "#{NONCE_CACHE_KEY}#{user_id}"
  end

  # GET /password/reset
  def new
  end

  # POST /password/reset
  #
  # Verify username + (live TOTP code OR backup code). On success,
  # mint the reset marker and redirect to the set-password form. On
  # any failure — unknown username, no-TOTP account, wrong code —
  # render the generic `reset failed.` with no oracle.
  def create
    username = params[:username].to_s.strip.downcase
    code     = params[:code].to_s.strip

    user = User.find_by(username: username) if username.present?

    # Unknown username: pay the same constant-time work a real
    # verification path would, then fail generically.
    if user.nil?
      bcrypt_dummy_compare
      audit("password_reset.failed", reason: "unknown_username", username_attempted: username)
      render_reset_failed
      return
    end

    # Known username without TOTP configured: there is genuinely no
    # reset path for such an account (no second factor to prove). Do
    # NOT leak that — same generic copy as the unknown-username branch.
    unless user.totp_configured?
      bcrypt_dummy_compare
      audit("password_reset.failed", reason: "no_totp", username_attempted: username, user_id: user.id)
      render_reset_failed
      return
    end

    unless verify_recovery_code(user, code)
      # Phase 29 — Unit A2 follow-up — security finding F2. Close the
      # remaining timing oracle on the wrong-code branch. Without this
      # compare, a "wrong-shape code" short-circuits before any
      # BCrypt work and the wall-clock response is observably faster
      # than the unknown-username / no-TOTP branches (which always
      # pay `bcrypt_dummy_compare`). An attacker could otherwise
      # distinguish "username exists AND has TOTP" from
      # "doesn't exist / has no TOTP" by timing alone. Always paying
      # the dummy compare on the wrong-code branch BEFORE rendering
      # symmetrizes all three failure paths.
      bcrypt_dummy_compare
      audit("password_reset.failed", reason: "wrong_code", username_attempted: username, user_id: user.id)
      render_reset_failed
      return
    end

    write_reset_marker(user)
    audit("password_reset.code_verified", user_id: user.id, ip: request.remote_ip)
    redirect_to edit_password_reset_path
  end

  # GET /password/reset/edit
  #
  # The set-new-password form, gated by a valid reset marker.
  def edit
    @user = load_reset_marker_user
    return if @user

    redirect_to password_reset_path, alert: "reset link expired. start again."
  end

  # PATCH /password/reset
  #
  # Apply the new password. Re-validate the reset marker, set the
  # password, consume the marker, revoke every session, reset the
  # per-username backoff bucket, and redirect to `/login` WITHOUT
  # establishing a session.
  def update
    @user = load_reset_marker_user
    unless @user
      redirect_to password_reset_path, alert: "reset link expired. start again."
      return
    end

    new_password              = params[:password].to_s
    new_password_confirmation = params[:password_confirmation].to_s

    if new_password.blank? || new_password != new_password_confirmation
      @user.errors.add(:password_confirmation, "does not match.")
      render :edit, status: :unprocessable_content
      return
    end

    @user.password              = new_password
    @user.password_confirmation = new_password_confirmation

    unless @user.save
      render :edit, status: :unprocessable_content
      return
    end

    # Consume the marker (cookie + cache nonce) so it cannot be
    # replayed to reset the password twice.
    consume_reset_marker(@user.id)

    # Defense-in-depth: wipe any half-state, then revoke every active
    # + pending Session row — a captured cookie must not survive a
    # password reset. Capture the not-yet-revoked count BEFORE the
    # revoke loop so the audit row carries the live tally (after the
    # loop, every session row's `revoked_at` is stamped, so a count of
    # the same scope would read zero).
    reset_session
    sessions_revoked_count = @user.sessions.where(revoked_at: nil).count
    @user.sessions.find_each(&:revoke!)

    # Phase 29 — Unit A2 follow-up — security finding F1. A password
    # reset must revoke EVERY bearer credential the user holds,
    # not only their cookie sessions. Without this block, a leaked
    # password + exfiltrated ApiToken / Doorkeeper grant survives the
    # reset and continues to grant full-scope access until manually
    # revoked at `/settings/tokens` (giving the user a false sense of
    # recovery). `update_all` is the bulk path — no per-row callbacks
    # are needed; the column write is the contract.
    tokens_revoked = ApiToken.where(user_id: @user.id, revoked_at: nil)
                             .update_all(revoked_at: Time.current)
    oauth_tokens_revoked = Doorkeeper::AccessToken
                             .where(resource_owner_id: @user.id, revoked_at: nil)
                             .update_all(revoked_at: Time.current)
    oauth_grants_revoked = Doorkeeper::AccessGrant
                             .where(resource_owner_id: @user.id, revoked_at: nil)
                             .update_all(revoked_at: Time.current)

    # The per-username backoff bucket is cleared — the user has
    # proven possession of their second factor.
    reset_backoff_for_username(@user.username)

    Auth::AuditLogger.call(
      acting_user: @user,
      source_surface: :web,
      action: :password_reset,
      target: @user,
      metadata: {
        reset_user_id: @user.id,
        sessions_revoked: sessions_revoked_count,
        api_tokens_revoked: tokens_revoked,
        oauth_access_tokens_revoked: oauth_tokens_revoked,
        oauth_access_grants_revoked: oauth_grants_revoked
      }
    )
    audit("password_reset.success", user_id: @user.id, ip: request.remote_ip)

    redirect_to login_path, notice: "password reset. log in with your new password."
  end

  private

  # True iff the code is a live TOTP code OR a valid (unused) backup
  # code. A backup code that matches is consumed (`used_at` stamped)
  # by `Auth::BackupCodeConsumer` so it cannot be reused — per R1.
  def verify_recovery_code(user, code)
    return false if code.blank?

    return true if Auth::TotpVerifier.call(user: user, code: code) == :ok

    Auth::BackupCodeConsumer.call(user: user, code: code) == :ok
  end

  def render_reset_failed
    flash.now[:alert] = "reset failed."
    render :new, status: :unprocessable_content
  end

  # Signed cookie + Rails.cache nonce, same pattern / TTL as
  # `SessionsController::PRE_AUTH_COOKIE`.
  def write_reset_marker(user)
    nonce = SecureRandom.urlsafe_base64(16)

    Rails.cache.write(
      self.class.reset_nonce_cache_key(user.id),
      nonce,
      expires_in: RESET_TTL
    )

    cookies.signed[RESET_COOKIE] = {
      value: {
        user_id: user.id,
        nonce: nonce,
        expires_at: RESET_TTL.from_now.to_i
      },
      httponly: true,
      same_site: :lax,
      secure: !Rails.env.test?,
      expires: RESET_TTL.from_now
    }
  end

  # Load + validate the reset marker. Returns the `User` on a valid
  # marker (cookie present, not expired, nonce matches the cache),
  # nil otherwise.
  def load_reset_marker_user
    raw = cookies.signed[RESET_COOKIE]
    return nil if raw.blank?

    payload = raw.is_a?(Hash) ? raw.symbolize_keys : nil
    return nil if payload.nil?

    user_id = payload[:user_id]
    nonce   = payload[:nonce].to_s
    return nil if user_id.blank? || nonce.blank?

    expires_at = payload[:expires_at].to_i
    return nil if expires_at.positive? && expires_at <= Time.current.to_i

    cache_nonce = Rails.cache.read(self.class.reset_nonce_cache_key(user_id)).to_s
    return nil if cache_nonce.blank?
    return nil unless ActiveSupport::SecurityUtils.secure_compare(nonce, cache_nonce)

    User.find_by(id: user_id)
  end

  def consume_reset_marker(user_id)
    cookies.delete(RESET_COOKIE)
    Rails.cache.delete(self.class.reset_nonce_cache_key(user_id))
  end

  def reset_backoff_for_username(username)
    normalized = username.to_s.strip.downcase
    return if normalized.blank?

    Auth::BackoffCalculator.reset!(
      key: "username:#{Digest::SHA256.hexdigest(normalized)}"
    )
  end

  def audit(event, **payload)
    return unless defined?(AUTH_AUDIT_LOGGER)

    AUTH_AUDIT_LOGGER.info({
      ts: Time.now.utc.iso8601(3),
      event: event
    }.merge(payload).to_json)
  rescue StandardError
    nil
  end
end
