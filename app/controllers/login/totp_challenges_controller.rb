# Post-password TOTP gate.
#
# After `SessionsController#create` validates the password for a user
# with TOTP enabled, it stashes a pre-auth marker and redirects here.
# Two inputs:
#
#   - 6-digit code from any TOTP authenticator app.
#   - or an 8-char backup code (fallback when the user does not have
#     access to their authenticator).
#
# Success path:
#
#   - Activates the session via `Pito::Auth::SessionActivator`.
#   - Rotates the session token (LD-12) via `reset_session` and a
#     fresh cookie. The pre-auth marker is cleared on success.
#
# Failure path:
#
#   - Renders 422 with the generic `login failed.` flash (LD-14).
#   - The pre-auth marker survives so the user can retry within the
#     marker's 10-minute TTL. The cookie nonce rotates on every fail
#     (F8) so a stolen cookie can do exactly one failed attempt
#     before being kicked back to /login.
#
# Auth: explicitly `allow_anonymous` — the user has NOT minted a
# session yet. The pre-auth marker is the only credential carried at
# this point.
class Login::TotpChallengesController < ApplicationController
  allow_anonymous :show, :create

  before_action :load_pre_auth_marker

  # GET /login/totp
  def show
    unless @pre_auth_user.totp_enabled?
      clear_pre_auth_marker
      redirect_to login_path,
                  alert: "2FA is not enabled for this account."
      nil
    end
  end

  # POST /login/totp
  def create
    unless @pre_auth_user.totp_enabled?
      clear_pre_auth_marker
      redirect_to login_path,
                  alert: "2FA is not enabled for this account."
      return
    end

    # P25 follow-up — F8. Verify the cookie-side nonce matches the
    # cache-side nonce. A mismatch (cache miss, stale nonce, replayed
    # cookie after rotation) is a hard 422 with the generic "login
    # failed." copy — same shape as a wrong-code failure so the
    # attacker cannot distinguish "nonce expired" from "code wrong".
    unless valid_nonce?
      flash.now[:alert] = "login failed."
      render :show, status: :unprocessable_content
      return
    end

    # Two distinct param names. The web form submits a 6-digit TOTP
    # as `code` (segmented hidden input) and an 8-char backup code as
    # `backup_code` (the `<details>` fallback below). Older JSON / spec
    # callers may pass either kind under `code` alone — preserve that
    # wire-format by falling back to `params[:code]` when
    # `params[:backup_code]` is blank. The TOTP attempt always runs
    # against `params[:code]`; an 8-char backup code submitted as
    # `code` simply fails the TOTP arm and gets tried by the backup
    # arm. Splitting the two names defends the web flow against the
    # Rack last-key-wins regression that an empty backup input would
    # otherwise inflict on the segmented hidden field.
    code = params[:code].to_s.strip
    backup_param = params[:backup_code].to_s.strip
    backup_candidate = backup_param.presence || code

    if try_totp(code) || try_backup_code(backup_candidate)
      # Phase 25 — 01g (LD-11). 2FA success clears the per-account
      # backoff bucket — the user has proven possession of the seed,
      # whatever earlier failures recorded should not gate them out.
      Pito::Auth::BackoffCalculator.reset!(
        key: "username:#{Digest::SHA256.hexdigest(@pre_auth_user.username.to_s.strip.downcase)}"
      )
      # P25 F8 — on success, drop the nonce cache entry. The
      # activator + cookie clearance happen in `activate_and_redirect`.
      Rails.cache.delete(
        SessionsController.pre_auth_nonce_cache_key(@pre_auth_user.id)
      )
      activate_and_redirect
    else
      # P25 F8 — rotate the nonce on every failed TOTP submit. Mint a
      # fresh nonce, write it to cache + the cookie, consuming the
      # old one. A stolen cookie can do exactly ONE failed attempt
      # before the nonce rotates and subsequent attempts hit the
      # invalid-nonce branch above. The legitimate user's NEXT submit
      # will carry the fresh cookie minted here, so they are not
      # locked out — only the attacker without browser context is.
      rotate_pre_auth_nonce!
      flash.now[:alert] = "login failed."
      render :show, status: :unprocessable_content
    end
  end

  private

  def try_totp(code)
    Pito::Auth::TotpVerifier.call(user: @pre_auth_user, code: code) == :ok
  end

  def try_backup_code(code)
    Pito::Auth::BackupCodeConsumer.call(user: @pre_auth_user, code: code) == :ok
  end

  def activate_and_redirect
    # LD-12 — token rotation on successful 2FA. The activator mints
    # a fresh active session row and returns the plaintext for the
    # new cookie; we reset the underlying Rails session before
    # writing the new cookie to wipe any half-state from the
    # pre-auth phase.
    reset_session

    session_record, plaintext = Pito::Auth::SessionActivator.call(
      user: @pre_auth_user,
      request: request
    )

    write_session_cookie(plaintext)
    clear_pre_auth_marker

    audit("session.login.totp_success",
          user_id: @pre_auth_user.id,
          session_id: session_record.id,
          ip: request.remote_ip)

    redirect_to(root_path, notice: "signed in.")
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

    expires_at = payload[:expires_at].to_i
    return nil if expires_at.positive? && expires_at <= Time.current.to_i

    payload
  end

  def clear_pre_auth_marker
    cookies.delete(SessionsController::PRE_AUTH_COOKIE)
  end

  def write_session_cookie(plaintext)
    cookies.signed[Sessions::Authenticator::COOKIE_NAME] = {
      value: plaintext,
      httponly: true,
      same_site: :lax,
      secure: !Rails.env.test?
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

  # P25 follow-up — F8. Cookie-side nonce must equal cache-side nonce.
  # A blank cookie-side nonce (legacy marker from before F8) is treated
  # as invalid so any pre-F8 cookies are forced to re-login. A blank
  # cache-side nonce (entry evicted / never written) is also invalid —
  # fail closed.
  def valid_nonce?
    cookie_nonce = @pre_auth_marker[:nonce].to_s
    return false if cookie_nonce.blank?

    cache_nonce = Rails.cache.read(
      SessionsController.pre_auth_nonce_cache_key(@pre_auth_user.id)
    ).to_s
    return false if cache_nonce.blank?

    ActiveSupport::SecurityUtils.secure_compare(cookie_nonce, cache_nonce)
  end

  # P25 follow-up — F8. Mint a fresh nonce, write it to cache + the
  # pre-auth cookie, consuming the old nonce. Idempotent — repeated
  # failed submits each rotate.
  def rotate_pre_auth_nonce!
    fresh_nonce = SecureRandom.urlsafe_base64(16)

    Rails.cache.write(
      SessionsController.pre_auth_nonce_cache_key(@pre_auth_user.id),
      fresh_nonce,
      expires_in: SessionsController::PRE_AUTH_TTL
    )

    new_payload = @pre_auth_marker.merge(nonce: fresh_nonce)
    cookies.signed[SessionsController::PRE_AUTH_COOKIE] = {
      value: new_payload,
      httponly: true,
      same_site: :lax,
      secure: !Rails.env.test?,
      expires: Time.at(new_payload[:expires_at].to_i)
    }
    @pre_auth_marker = new_payload
  rescue StandardError => e
    Rails.logger.warn(
      "[Login::TotpChallengesController] nonce rotation failed: #{e.class}: #{e.message}"
    )
    nil
  end
end
