# Phase 12 — Step A (6a-sessions-and-login-ui.md) — login / logout.
#
# `new` and `create` are anonymous (the login form has to render before
# the user is authenticated). `destroy` is gated by the standard
# session auth — the user must have a valid session to log out.
#
# Phase 25 — 01a. Every authenticate POST writes a `LoginAttempt` row
# via `Auth::AttemptLogger`, regardless of outcome. The logger is the
# single entry point — this controller MUST NOT bypass it for any
# auth-related write to `LoginAttempt`. The logger also short-circuits
# blocked-pair attempts to `result: blocked` so the user-visible
# response stays generic (LD-14).
#
# Phase 25 — 01b. After a correct password the controller no longer
# unconditionally mints a session. It asks `Auth::NewLocationDetector`
# which of three terminal states the request lands in:
#
#   1. `:trusted`      — `Auth::SessionActivator` mints a fresh active
#                        session, stamps the trusted-location, writes
#                        the attempt row, sets the auth cookie, and
#                        redirects to root.
#   2. `:new_location` — the controller stashes a pre-auth marker
#                        (signed cookie carrying user_id + fingerprint
#                        + ip_prefix), then redirects to
#                        `/login/challenge`. NO session is minted yet.
#   3. `:blocked_pair` — the controller writes a `blocked` attempt row
#                        and renders the generic `login failed.` flash.
#
# User-visible failure copy is `Login failed.` (LD-14) regardless of
# which step failed (wrong password, unknown email, blocked pair,
# rate-limited). The precise reason lives on the persisted
# `LoginAttempt` row, NOT in the response or flash.
class SessionsController < ApplicationController
  # Phase 29 — Unit A2 follow-up — security finding F6. The
  # constant-ish-time dummy bcrypt compare used by the unknown-username
  # branch to symmetrize wall-clock cost with `User#authenticate` now
  # lives in a shared concern. Previously the method body was
  # duplicated here and in `PasswordResetsController`; a future edit
  # to one and not the other risked introducing timing asymmetry
  # between the two surfaces. See
  # `app/controllers/concerns/sessions/bcrypt_dummy_compare.rb`.
  include Sessions::BcryptDummyCompare

  # Phase 25 — 01b. Signed cookie that carries the post-password-check
  # pre-auth marker. Read by `Login::ChallengesController#show` and
  # `#create`; cleared by either branch's terminal action (TOTP
  # success / approve / cancel) so a stale marker can't be replayed.
  PRE_AUTH_COOKIE = :pito_pre_auth
  PRE_AUTH_TTL    = 10.minutes

  # P25 follow-up — F8. Pre-auth nonce rotation. The cookie carries a
  # random nonce; the same nonce is mirrored in Rails.cache under
  # `preauth_nonce:<user_id>` with the same 10-min TTL. On every TOTP
  # submit, the controller verifies cookie-nonce == cache-nonce. On
  # FAILURE: rotate (write a fresh nonce to cache + cookie, consuming
  # the old one) — bounding a stolen cookie's brute force to ~1
  # attempt before the nonce rotates out from under it. On SUCCESS:
  # delete the cache entry (the pre-auth marker is consumed).
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
      log_attempt(result: :failed, reason: :rate_limited, username: params[:username].to_s)
      render_throttled
      return
    end

    username = params[:username].to_s.strip.downcase
    password = params[:password].to_s
    remember = params[:remember_me].to_s == "yes"

    user = User.find_by(username: username) if username.present?

    if user.nil?
      bcrypt_dummy_compare
      log_attempt(result: :failed, reason: :unknown_account, username: username)
      audit("session.login.failed", reason: "unknown_username", username_attempted: username)
      mark_failure_and_render_invalid(username: username)
      return
    end

    unless user.authenticate(password)
      log_attempt(result: :failed, reason: :wrong_password, username: username, user: user)
      audit("session.login.failed", reason: "wrong_password", username_attempted: username, user_id: user.id)
      mark_failure_and_render_invalid(username: username)
      return
    end

    # Phase 25 — 01b. Post-password-check dispatch: trusted / new
    # location / blocked. The detector reads the same fingerprint +
    # ip_prefix the logger uses; both layers consult `BlockedLocation`
    # independently so a regression in either still fails closed.
    fingerprint_hash = current_request_fingerprint
    ip_prefix        = current_request_ip_prefix

    # Phase 25 — 01e. TOTP 2FA gate. When the user has 2FA on, the
    # password-only path is NOT enough — we stash the pre-auth marker
    # and bounce to `/login/totp`. The TOTP controller runs
    # `Auth::SessionActivator` (or `Auth::SessionPendingApprover` if
    # the location is also new and the user backs out of TOTP) only
    # AFTER a valid 6-digit code or backup code. The TOTP gate
    # applies on every login — trusted or new location — so a stolen
    # device cookie cannot bypass it.
    if user.totp_enabled?
      write_pre_auth_marker(
        user_id: user.id,
        fingerprint_hash: fingerprint_hash,
        ip_prefix: ip_prefix,
        remember: remember
      )
      audit("session.login.totp_challenge", user_id: user.id, ip: request.remote_ip)
      redirect_to login_totp_path
      return
    end

    decision = Auth::NewLocationDetector.call(
      user: user,
      fingerprint_hash: fingerprint_hash,
      ip_prefix: ip_prefix
    )

    case decision
    when :blocked_pair
      log_attempt(result: :blocked, reason: :blocked_pair, username: username, user: user)
      audit("session.login.blocked", user_id: user.id, ip: request.remote_ip)
      mark_failure_and_render_invalid(username: username)
      nil

    when :new_location
      # Phase 29 — Unit A2 (R4). First-login bootstrap. A user who has
      # NOT configured TOTP cannot meaningfully participate in
      # new-location approval — on a fresh seed there is no second
      # device and no approver. Instead of stashing a pre-auth marker
      # and routing to `/login/challenge`, we mint an ACTIVE session
      # directly so the post-session `require_totp_configured!` gate
      # immediately forces TOTP enrollment. The attempt row carries
      # `reason: :first_login_totp_setup_required` for forensic
      # clarity.
      unless user.totp_configured?
        bootstrap_first_login_session(
          user: user,
          fingerprint_hash: fingerprint_hash,
          ip_prefix: ip_prefix,
          remember: remember
        )
        return
      end

      # Stash a pre-auth marker (signed cookie). NO session row, NO
      # auth cookie. The `/login/challenge` page reads the marker to
      # remember which user passed the password gate and offers the
      # two challenge paths (TOTP in 01e, ask-for-approval here).
      # Marker self-expires at 10 minutes; either branch's terminal
      # action clears it.
      write_pre_auth_marker(
        user_id: user.id,
        fingerprint_hash: fingerprint_hash,
        ip_prefix: ip_prefix,
        remember: remember
      )
      audit("session.login.new_location_challenge", user_id: user.id, ip: request.remote_ip)
      redirect_to login_challenge_path
      nil

    when :trusted
      session_record, plaintext = Auth::SessionActivator.call(
        user: user,
        request: request,
        fingerprint_hash: fingerprint_hash,
        ip_prefix: ip_prefix,
        reason: :trusted_location_success,
        remember: remember
      )

      # Defense-in-depth: `Auth::AttemptLogger` inside the activator
      # ALSO consults the block list. If the logger rewrote its row
      # to `blocked`, the controller refuses to set the cookie even
      # though the detector said `:trusted`.
      last_attempt = LoginAttempt.where(session_id: session_record.id).recent.first
      if last_attempt&.result_blocked?
        session_record.revoke!
        audit("session.login.blocked", user_id: user.id, ip: request.remote_ip)
        mark_failure_and_render_invalid(username: username)
        return
      end

      # Phase 25 — 01g (LD-11). A successful login clears the
      # per-account backoff bucket so a legitimate user who typo'd a
      # few times before remembering their password is not locked out
      # indefinitely.
      reset_backoff_for_username(username)

      write_session_cookie(plaintext, remember: remember)
      audit(
        "session.login.success",
        user_id: user.id,
        session_id: session_record.id,
        ip: request.remote_ip,
        ua: session_record.user_agent.to_s,
        remember: remember
      )

      redirect_to(intended_url_target || root_path, notice: "signed in.")
    end
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

  # Wrap the logger so we can swallow any unexpected error rather than
  # destroy the auth path. Logging is observability; a logger blowup
  # must not prevent the user from seeing the generic failure flash.
  def log_attempt(result:, reason:, username: nil, user: nil)
    Auth::AttemptLogger.call(
      request: request,
      result: result,
      reason: reason,
      username: username,
      user: user
    )
  rescue StandardError => e
    Rails.logger.error("[SessionsController] AttemptLogger failed: #{e.class}: #{e.message}")
    nil
  end

  # Phase 29 — Unit A2 (R4). First-login bootstrap. The user passed
  # the password check, has no TOTP configured, and landed on a
  # `:new_location` classification (a fresh seed has no
  # `TrustedLocation` rows). Mint an ACTIVE session directly — the
  # post-session `require_totp_configured!` gate then forces TOTP
  # enrollment. No pre-auth marker, no pending-approval detour: there
  # is no approver for a brand-new account. The attempt row carries
  # `reason: :first_login_totp_setup_required`.
  def bootstrap_first_login_session(user:, fingerprint_hash:, ip_prefix:, remember:)
    session_record, plaintext = Auth::SessionActivator.call(
      user: user,
      request: request,
      fingerprint_hash: fingerprint_hash,
      ip_prefix: ip_prefix,
      reason: :first_login_totp_setup_required,
      remember: remember
    )

    reset_backoff_for_username(user.username)
    write_session_cookie(plaintext, remember: remember)
    audit(
      "session.login.first_login_totp_setup_required",
      user_id: user.id,
      session_id: session_record.id,
      ip: request.remote_ip
    )

    redirect_to settings_security_totp_path,
                notice: "set up two-factor authentication to continue."
  end

  def mark_failure_and_render_invalid(username:)
    request.env["pito.auth_failed"] = true
    SessionThrottle.record_failure(request.remote_ip)

    # Phase 25 — 01g (LD-11). Each failed login bumps the per-account
    # backoff bucket. The bucket TTL is the current backoff window, so
    # a quiet user resets naturally; an attacker pays exponentially.
    Auth::BackoffCalculator.record_trip!(key: backoff_username_key(username))

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
    # Phase 25 — 01g (LD-11). When the legacy in-controller throttle
    # trips, also record an explicit `LoginAttempt` row with
    # `reason: :rate_limited` so the attempt log carries the row even
    # if the operator never bumped into the rack-attack throttle that
    # writes its own.
    Auth::RateLimitLogger.call(request: request, username: params[:username])
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
    Auth::BackoffCalculator.reset!(key: key)
  end

  def write_session_cookie(plaintext, remember:)
    cookies.signed[Sessions::Authenticator::COOKIE_NAME] = {
      value: plaintext,
      httponly: true,
      same_site: :lax,
      secure: !Rails.env.test?,
      expires: remember ? Session::REMEMBER_ME_TTL.from_now : nil
    }
  end

  # Phase 25 — 01b. Compose the (fingerprint, ip_prefix) pair the
  # detector reads. Stays in lockstep with `Auth::AttemptLogger`'s
  # own composition so the two layers always agree.
  def current_request_fingerprint
    Auth::FingerprintComposer.call(
      request: request,
      screen_hint: params["fp_screen"],
      locale_hint: params["fp_locale"]
    )
  end

  def current_request_ip_prefix
    Auth::AttemptLogger.safe_prefix(request.remote_ip.to_s.presence || "0.0.0.0")
  end

  # Phase 25 — 01b. Stash a signed pre-auth marker carrying just enough
  # state for `/login/challenge` to resume: user id, fingerprint, ip
  # prefix, remember-me flag, expiry stamp. No password, no session
  # row. Marker self-expires at `PRE_AUTH_TTL`.
  #
  # P25 follow-up — F8. The marker now also carries a per-mint random
  # `nonce`. The same nonce is mirrored in `Rails.cache` keyed on
  # `preauth_nonce:<user_id>` with the same 10-min TTL. On every TOTP
  # submit, the TOTP controller verifies the cookie's nonce matches
  # the cache's nonce. On failure it rotates BOTH (fresh nonce → cache
  # + cookie re-mint), so a stolen cookie's brute-force is bounded
  # to ~1 attempt before the nonce rotates out from under it.
  def write_pre_auth_marker(user_id:, fingerprint_hash:, ip_prefix:, remember: false)
    nonce = SecureRandom.urlsafe_base64(16)

    payload = {
      user_id: user_id,
      fingerprint_hash: fingerprint_hash,
      ip_prefix: ip_prefix,
      remember: remember ? "yes" : "no",
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
