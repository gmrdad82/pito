# Phase 12 — Step A (6a-sessions-and-login-ui.md) — login / logout.
#
# `new` and `create` are anonymous (the login form has to render before
# the user is authenticated). `destroy` is gated by the standard
# session auth — the user must have a valid session to log out.
#
# The form posts `identifier` (email OR username), `password`,
# `remember_me` (yes/no). Failure paths emit a generic "invalid email
# or password." regardless of whether the identifier matched a User row,
# plus a constant-time dummy bcrypt compare so the response timing
# doesn't leak account existence. Every failure flips
# `request.env["pito.auth_failed"] = true` so the rack-attack throttle
# counts only failures.
class SessionsController < ApplicationController
  allow_anonymous :new, :create

  # GET /login
  def new
    @identifier = params[:identifier].to_s
  end

  # POST /login
  def create
    if SessionThrottle.exhausted?(request.remote_ip)
      render_throttled
      return
    end

    identifier = params[:identifier].to_s.strip
    password = params[:password].to_s
    remember = params[:remember_me].to_s == "yes"

    user = User.unscoped.find_by_username_or_email(identifier) if identifier.present?

    if user.nil?
      bcrypt_dummy_compare
      audit("session.login.failed", reason: "unknown_identifier", identifier_attempted: identifier)
      mark_failure_and_render_invalid(identifier: identifier)
      return
    end

    unless user.authenticate(password)
      audit("session.login.failed", reason: "wrong_password", identifier_attempted: identifier, user_id: user.id)
      mark_failure_and_render_invalid(identifier: identifier)
      return
    end

    session_record, plaintext = Session.create_for!(
      user: user,
      ip: request.remote_ip,
      user_agent: request.user_agent.to_s.first(1024),
      remember: remember
    )

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

  def mark_failure_and_render_invalid(identifier:)
    request.env["pito.auth_failed"] = true
    SessionThrottle.record_failure(request.remote_ip)

    if SessionThrottle.exhausted?(request.remote_ip)
      render_throttled
      return
    end

    @identifier = identifier
    flash.now[:alert] = "invalid email or password."
    render :new, status: :unprocessable_content
  end

  def render_throttled
    audit("session.login.throttled", ip: request.remote_ip)
    response.headers["Retry-After"] = SessionThrottle::WINDOW.to_i.to_s
    render plain: "rate_limited — try again in #{SessionThrottle::WINDOW.to_i} seconds.",
           status: :too_many_requests
  end

  # Constant-ish-time dummy bcrypt to avoid leaking via timing whether
  # the email exists. BCrypt::Password.create (default cost 12) takes
  # ~100ms; the comparison is what we want, not the create — but
  # `BCrypt::Password.new(...).is_password?` over a precomputed hash
  # gives roughly the same compare time without spawning a write-side
  # bcrypt round.
  #
  # Lazy memoization (`||=`) keeps Rails boot fast: the bcrypt hash is
  # only computed the first time a failed login lands. MIN_COST is
  # deliberate — this digest exists only to equalize timing between the
  # "wrong email" and "wrong password" branches; its hash quality is
  # irrelevant.
  def self.dummy_bcrypt_hash
    @dummy_bcrypt_hash ||= BCrypt::Password.create("dummy-password-noop", cost: BCrypt::Engine::MIN_COST)
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
