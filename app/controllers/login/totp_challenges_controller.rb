# Phase 25 — 01e. TOTP gate on the new-location login flow.
#
# After `SessionsController#create` decides the (fingerprint, ip_prefix)
# pair is new AND `Login::ChallengesController` routes to the 2FA path,
# the user lands here. Two inputs:
#
#   - 6-digit code from any TOTP authenticator app.
#   - or an 8-char backup code (fallback when the user does not have
#     access to their authenticator).
#
# Success path:
#
#   - Activates the session via `Auth::SessionActivator` with
#     `reason: :new_location_2fa_passed`. The activator handles
#     trusted-location upsert + LoginAttempt write.
#   - Rotates the session token (LD-12) via `reset_session` and a
#     fresh cookie. The pre-auth marker is cleared on success.
#   - Pending-approval flow is bypassed entirely — 2FA success is
#     the strongest signal we have that the user is who they say.
#
# Failure path:
#
#   - Writes a `LoginAttempt` row with `reason: :twofa_failed`.
#     Renders 422 with the generic `login failed.` flash (LD-14).
#   - The pre-auth marker survives so the user can retry within the
#     marker's 10-minute TTL.
#
# Auth: explicitly `allow_anonymous` — the user has NOT minted a
# session yet. The pre-auth marker is the only credential carried at
# this point.
class Login::TotpChallengesController < ApplicationController
  allow_anonymous :show, :create

  before_action :load_pre_auth_marker

  # GET /login/totp
  def show
    # 2FA must be on. If the user is in the new-location flow but
    # never enrolled, push them back to the challenge page so they
    # can pick `[ask for approval]`.
    unless @pre_auth_user.totp_enabled?
      redirect_to login_challenge_path,
                  alert: "2FA is not enabled for this account."
    end
  end

  # POST /login/totp
  def create
    unless @pre_auth_user.totp_enabled?
      redirect_to login_challenge_path,
                  alert: "2FA is not enabled for this account."
      return
    end

    code = params[:code].to_s.strip

    if try_totp(code) || try_backup_code(code)
      activate_and_redirect
    else
      log_failed_attempt
      flash.now[:alert] = "login failed."
      render :show, status: :unprocessable_content
    end
  end

  private

  def try_totp(code)
    Auth::TotpVerifier.call(user: @pre_auth_user, code: code) == :ok
  end

  def try_backup_code(code)
    # Backup codes are 8 chars from the safe alphabet — never 6 pure
    # digits — so we only fall through to backup when the input fails
    # the TOTP shape OR when the TOTP verifier returns `:invalid`.
    # Either way, the consumer is the second attempt; on `:ok` it
    # stamps `used_at` and returns truthy.
    Auth::BackupCodeConsumer.call(user: @pre_auth_user, code: code) == :ok
  end

  def activate_and_redirect
    # LD-12 — token rotation on successful 2FA. The activator mints
    # a fresh active session row and returns the plaintext for the
    # new cookie; we reset the underlying Rails session before
    # writing the new cookie to wipe any half-state from the
    # pre-auth phase.
    reset_session

    fingerprint_hash = @pre_auth_marker[:fingerprint_hash]
    ip_prefix        = @pre_auth_marker[:ip_prefix]
    remember         = @pre_auth_marker[:remember].to_s == "yes"

    session_record, plaintext = Auth::SessionActivator.call(
      user: @pre_auth_user,
      request: request,
      fingerprint_hash: fingerprint_hash,
      ip_prefix: ip_prefix,
      reason: :new_location_2fa_passed,
      remember: remember
    )

    write_session_cookie(plaintext, remember: remember)
    clear_pre_auth_marker

    audit("session.login.totp_success",
          user_id: @pre_auth_user.id,
          session_id: session_record.id,
          ip: request.remote_ip)

    redirect_to(root_path, notice: "signed in.")
  end

  def log_failed_attempt
    Auth::AttemptLogger.call(
      request: request,
      result: :failed,
      reason: :twofa_failed,
      user: @pre_auth_user,
      email: @pre_auth_user.email
    )
  rescue StandardError => e
    Rails.logger.warn("[Login::TotpChallengesController] AttemptLogger failed: #{e.class}: #{e.message}")
    nil
  end

  def load_pre_auth_marker
    @pre_auth_marker = read_pre_auth_marker

    if @pre_auth_marker.nil?
      respond_to do |format|
        format.html { redirect_to login_path, alert: "please log in." }
        format.json { render json: { error: "unauthorized" }, status: :unauthorized }
        format.any  { head :unauthorized }
      end
      return
    end

    @pre_auth_user = User.find_by(id: @pre_auth_marker[:user_id])
    if @pre_auth_user.nil?
      clear_pre_auth_marker
      redirect_to login_path, alert: "please log in."
    end
  end

  def read_pre_auth_marker
    raw = cookies.signed[SessionsController::PRE_AUTH_COOKIE]
    return nil if raw.blank?

    payload = raw.is_a?(Hash) ? raw.symbolize_keys : nil
    return nil if payload.nil?
    return nil if payload[:user_id].blank?
    return nil if payload[:fingerprint_hash].blank?
    return nil if payload[:ip_prefix].blank?

    expires_at = payload[:expires_at].to_i
    return nil if expires_at.positive? && expires_at <= Time.current.to_i

    payload
  end

  def clear_pre_auth_marker
    cookies.delete(SessionsController::PRE_AUTH_COOKIE)
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
