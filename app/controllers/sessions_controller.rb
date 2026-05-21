# Login / logout.
#
# `new` and `create` are anonymous (the login form has to render before
# the user is authenticated). `destroy` is gated by the standard
# session auth — the user must have a valid session to log out.
#
# Post-Phase-25 rollback. The new-location approval flow + the
# LoginAttempt forensic surface are gone. The simplified login flow:
#
#   1. password verifies        → if user has TOTP, stash pre-auth
#                                 marker + redirect to `/login/totp`.
#                               → else, mint an active session directly.
#   2. /login/totp succeeds    → mint an active session (token
#                                 rotation per LD-12).
#
# Sad paths bottom out through the same generic `login failed.`
# response with no oracle differentiation (LD-14). The only writes the
# controller still makes are `AuthAuditLog` rows (high-level audit via
# `Pito::Auth::AuditLogger` — distinct from the dropped per-attempt log).
class SessionsController < ApplicationController
  # Phase 29 — Unit A2 follow-up — security finding F6. The
  # constant-ish-time dummy bcrypt compare used by the unknown-username
  # branch to symmetrize wall-clock cost with `User#authenticate` lives
  # in a shared concern (also used by `PasswordResetsController`).
  include Sessions::BcryptDummyCompare

  # Signed cookie that carries the post-password-check pre-auth marker
  # for users with TOTP. Read by `Login::TotpChallengesController`;
  # cleared on TOTP success or marker expiry.
  PRE_AUTH_COOKIE = :pito_pre_auth
  PRE_AUTH_TTL    = 10.minutes

  # P25 follow-up — F8. Pre-auth nonce rotation. The cookie carries a
  # random nonce; the same nonce is mirrored in Rails.cache under
  # `preauth_nonce:<user_id>` with the same 10-min TTL. On every TOTP
  # submit, the controller verifies cookie-nonce == cache-nonce. On
  # FAILURE: rotate (write a fresh nonce to cache + cookie, consuming
  # the old one). On SUCCESS: delete the cache entry (consumed).
  PRE_AUTH_NONCE_CACHE_PREFIX = "preauth_nonce:".freeze

  def self.pre_auth_nonce_cache_key(user_id)
    "#{PRE_AUTH_NONCE_CACHE_PREFIX}#{user_id}"
  end

  allow_anonymous :new, :create

  # GET /login
  def new
    @username = params[:username].to_s
  end

  # POST /login
  def create
    if SessionThrottle.exhausted?(request.remote_ip)
      render_throttled
      return
    end

    username = params[:username].to_s.strip.downcase
    password = params[:password].to_s

    user = User.find_by(username: username) if username.present?

    if user.nil?
      bcrypt_dummy_compare
      audit("session.login.failed", reason: "unknown_username", username_attempted: username)
      mark_failure_and_render_invalid(username: username)
      return
    end

    unless user.authenticate(password)
      audit("session.login.failed", reason: "wrong_password", username_attempted: username, user_id: user.id)
      mark_failure_and_render_invalid(username: username)
      return
    end

    # TOTP gate. When the user has 2FA on, the password-only path is
    # NOT enough — stash a pre-auth marker and bounce to `/login/totp`.
    # The TOTP controller mints the session AFTER a valid 6-digit code
    # or backup code. The TOTP gate applies on every login, so a stolen
    # device cookie cannot bypass it.
    if user.totp_enabled?
      write_pre_auth_marker(user_id: user.id)
      audit("session.login.totp_challenge", user_id: user.id, ip: request.remote_ip)
      redirect_to login_totp_path
      return
    end

    # Phase 29 — Unit A2 (R4). First-login bootstrap. A user who has
    # not yet configured TOTP lands on an active session directly so
    # the post-session `require_totp_configured!` gate immediately
    # forces TOTP enrollment.
    bootstrap_first_login_session(user: user)
  end

  # DELETE /session
  def destroy
    session_row = Current.session

    if session_row
      session_row.revoke!
      audit(
        "session.logout",
        user_id: session_row.user_id,
        session_id: session_row.id,
        ip: request.remote_ip
      )
    end

    cookies.delete(Sessions::Authenticator::COOKIE_NAME)
    redirect_to login_path, notice: "signed out."
  end

  private

  # First-login + no-TOTP login both mint an active session directly.
  # The post-session `require_totp_configured!` gate handles the rest
  # (forces enrollment when the user has no TOTP).
  def bootstrap_first_login_session(user:)
    session_record, plaintext = Pito::Auth::SessionActivator.call(
      user: user,
      request: request
    )

    reset_backoff_for_username(user.username)
    write_session_cookie(plaintext)

    if user.totp_configured?
      audit(
        "session.login.success",
        user_id: user.id,
        session_id: session_record.id,
        ip: request.remote_ip,
        ua: session_record.user_agent.to_s
      )

      redirect_to(intended_url_target || root_path, notice: "signed in.")
    else
      audit(
        "session.login.first_login_totp_setup_required",
        user_id: user.id,
        session_id: session_record.id,
        ip: request.remote_ip
      )

      # The mandatory-2FA gate uses this redirect for every entry point
      # that lands on a user without TOTP configured.
      redirect_to settings_path(enroll_totp: 1),
                  notice: "set up two-factor authentication to continue."
    end
  end

  def mark_failure_and_render_invalid(username:)
    request.env["pito.auth_failed"] = true
    SessionThrottle.record_failure(request.remote_ip)

    # Phase 25 — 01g (LD-11). Each failed login bumps the per-account
    # backoff bucket. The bucket TTL is the current backoff window, so
    # a quiet user resets naturally; an attacker pays exponentially.
    Pito::Auth::BackoffCalculator.record_trip!(key: backoff_username_key(username))

    if SessionThrottle.exhausted?(request.remote_ip)
      render_throttled
      return
    end

    @username = username
    flash.now[:alert] = "login failed."
    render :new, status: :unprocessable_content
  end

  def render_throttled
    audit("session.login.throttled", ip: request.remote_ip)
    response.headers["Retry-After"] = SessionThrottle::WINDOW.to_i.to_s
    render plain: "login failed.",
           status: :too_many_requests
  end

  def backoff_username_key(username)
    normalized = username.to_s.strip.downcase
    return "" if normalized.blank?

    "username:#{Digest::SHA256.hexdigest(normalized)}"
  end

  def reset_backoff_for_username(username)
    key = backoff_username_key(username)
    return if key.empty?
    Pito::Auth::BackoffCalculator.reset!(key: key)
  end

  def write_session_cookie(plaintext)
    cookies.signed[Sessions::Authenticator::COOKIE_NAME] = {
      value: plaintext,
      httponly: true,
      same_site: :lax,
      secure: !Rails.env.test?
    }
  end

  # Stash a signed pre-auth marker carrying just enough state for
  # `/login/totp` to resume: user id, expiry stamp. No password, no
  # session row. Marker self-expires at `PRE_AUTH_TTL`.
  #
  # P25 follow-up — F8. The marker also carries a per-mint random
  # `nonce`. The same nonce is mirrored in `Rails.cache` keyed on
  # `preauth_nonce:<user_id>` with the same 10-min TTL. On every TOTP
  # submit, the TOTP controller verifies the cookie's nonce matches
  # the cache's nonce. On failure it rotates BOTH (fresh nonce → cache
  # + cookie re-mint), bounding a stolen cookie's brute-force to ~1
  # attempt before the nonce rotates out from under it.
  def write_pre_auth_marker(user_id:)
    nonce = SecureRandom.urlsafe_base64(16)

    payload = {
      user_id: user_id,
      expires_at: PRE_AUTH_TTL.from_now.to_i,
      nonce: nonce
    }

    Rails.cache.write(
      self.class.pre_auth_nonce_cache_key(user_id),
      nonce,
      expires_in: PRE_AUTH_TTL
    )

    cookies.signed[PRE_AUTH_COOKIE] = {
      value: payload,
      httponly: true,
      same_site: :lax,
      secure: !Rails.env.test?,
      expires: PRE_AUTH_TTL.from_now
    }
  end

  def intended_url_target
    target = cookies.signed[Sessions::AuthConcern::INTENDED_URL_COOKIE].presence
    cookies.delete(Sessions::AuthConcern::INTENDED_URL_COOKIE)
    return nil if target.blank?
    return nil unless target.start_with?("/")
    return nil if target.start_with?(login_path)

    target
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
