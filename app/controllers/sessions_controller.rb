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
  # Phase 25 — 01b. Signed cookie that carries the post-password-check
  # pre-auth marker. Read by `Login::ChallengesController#show` and
  # `#create`; cleared by either branch's terminal action (TOTP
  # success / approve / cancel) so a stale marker can't be replayed.
  PRE_AUTH_COOKIE = :pito_pre_auth
  PRE_AUTH_TTL    = 10.minutes

  allow_anonymous :new, :create

  # GET /login
  def new
    @email = params[:email].to_s
  end

  # POST /login
  def create
    if SessionThrottle.exhausted?(request.remote_ip)
      log_attempt(result: :failed, reason: :rate_limited, email: params[:email].to_s)
      render_throttled
      return
    end

    email = params[:email].to_s.strip
    password = params[:password].to_s
    remember = params[:remember_me].to_s == "yes"

    user = User.find_by(email: email) if email.present?

    if user.nil?
      bcrypt_dummy_compare
      log_attempt(result: :failed, reason: :unknown_account, email: email)
      audit("session.login.failed", reason: "unknown_email", email_attempted: email)
      mark_failure_and_render_invalid(email: email)
      return
    end

    unless user.authenticate(password)
      log_attempt(result: :failed, reason: :wrong_password, email: email, user: user)
      audit("session.login.failed", reason: "wrong_password", email_attempted: email, user_id: user.id)
      mark_failure_and_render_invalid(email: email)
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
      log_attempt(result: :blocked, reason: :blocked_pair, email: email, user: user)
      audit("session.login.blocked", user_id: user.id, ip: request.remote_ip)
      mark_failure_and_render_invalid(email: email)
      nil

    when :new_location
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
        mark_failure_and_render_invalid(email: email)
        return
      end

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
  def log_attempt(result:, reason:, email: nil, user: nil)
    Auth::AttemptLogger.call(
      request: request,
      result: result,
      reason: reason,
      email: email,
      user: user
    )
  rescue StandardError => e
    Rails.logger.error("[SessionsController] AttemptLogger failed: #{e.class}: #{e.message}")
    nil
  end

  def mark_failure_and_render_invalid(email:)
    request.env["pito.auth_failed"] = true
    SessionThrottle.record_failure(request.remote_ip)

    if SessionThrottle.exhausted?(request.remote_ip)
      render_throttled
      return
    end

    @email = email
    flash.now[:alert] = "login failed."
    render :new, status: :unprocessable_content
  end

  def render_throttled
    audit("session.login.throttled", ip: request.remote_ip)
    response.headers["Retry-After"] = SessionThrottle::WINDOW.to_i.to_s
    render plain: "login failed.",
           status: :too_many_requests
  end

  # Constant-ish-time dummy bcrypt to avoid leaking via timing whether
  # the email exists. The comparison is what we want — not the create —
  # so `BCrypt::Password.new(...).is_password?` over a precomputed hash
  # gives roughly the same compare time as `User#authenticate`.
  #
  # The cost MUST match the cost `has_secure_password` uses to hash real
  # passwords. `ActiveModel::SecurePassword` picks `BCrypt::Engine::MIN_COST`
  # when `min_cost = true` (the test-suite speed switch) and
  # `BCrypt::Engine.cost` otherwise — which resolves to
  # `BCrypt::Engine::DEFAULT_COST` (12) in production unless someone
  # globally overrides it. Mirroring that selection here keeps the dummy
  # compare's wall time within the same order of magnitude as a real
  # `User#authenticate`, closing the account-enumeration timing oracle.
  #
  # Lazy class-level memoization (`||=`) is deliberate: the hash is
  # computed once on the first failed login (so Rails boot stays fast)
  # and reused on every subsequent dummy compare (so we never pay the
  # `create` cost per-request — only the cheap-er `is_password?` compare,
  # which is what we want to symmetrize against `User#authenticate`).
  def self.dummy_bcrypt_cost
    if ActiveModel::SecurePassword.min_cost
      BCrypt::Engine::MIN_COST
    else
      BCrypt::Engine.cost
    end
  end

  def self.dummy_bcrypt_hash
    @dummy_bcrypt_hash ||= BCrypt::Password.create("dummy-password-noop", cost: dummy_bcrypt_cost)
  end

  def bcrypt_dummy_compare
    BCrypt::Password.new(self.class.dummy_bcrypt_hash).is_password?("dummy-password-noop")
    nil
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
  def write_pre_auth_marker(user_id:, fingerprint_hash:, ip_prefix:, remember: false)
    payload = {
      user_id: user_id,
      fingerprint_hash: fingerprint_hash,
      ip_prefix: ip_prefix,
      remember: remember ? "yes" : "no",
      expires_at: PRE_AUTH_TTL.from_now.to_i
    }

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
