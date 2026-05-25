# Login / logout.
#
# Post-Z1 architecture. There is no User model and no password check.
# Authentication is purely TOTP-based: the owner proves possession of
# the enrolled authenticator (6-digit code) or a backup code (8-char).
#
# Login flow (single step):
#
#   POST /login  params[:code]         — 6-digit TOTP
#                params[:backup_code]  — 8-char backup code (fallback)
#
#   1. If AppSetting.totp_enabled? is false → 422 with operator hint.
#   2. Try TotpVerifier; on :ok → activate.
#   3. Try BackupCodeConsumer; on :ok → activate.
#   4. Any fail → bump per-IP throttle + generic 422.
#
# DELETE /session — logout (existing session required).
class SessionsController < ApplicationController
  allow_anonymous :new, :create

  # GET /login
  #
  # No longer renders a username/password form. The dialog renders on
  # the root path; this action redirects there so old bookmarks / test
  # suite paths land cleanly.
  def new
    redirect_to root_path
  end

  # POST /login
  def create
    if SessionThrottle.exhausted?(request.remote_ip)
      render_throttled
      return
    end

    unless AppSetting.totp_enabled?
      render plain: "no TOTP enrolled — run bin/rails pito:auth:enroll",
             status: :unprocessable_content
      return
    end

    code          = params[:code].to_s.strip
    backup_param  = params[:backup_code].to_s.strip
    backup_candidate = backup_param.presence || code

    if try_totp(code) || try_backup_code(backup_candidate)
      activate_and_redirect
    else
      mark_failure_and_render_invalid
    end
  end

  # DELETE /session
  def destroy
    session_row = Current.session

    if session_row
      session_row.revoke!
      audit(
        "session.logout",
        session_id: session_row.id,
        ip: request.remote_ip
      )
    end

    cookies.delete(Sessions::Authenticator::COOKIE_NAME)
    redirect_to login_path
  end

  private

  def try_totp(code)
    return false if code.blank?

    Pito::Auth::TotpVerifier.call(code: code) == :ok
  end

  def try_backup_code(code)
    return false if code.blank?

    Pito::Auth::BackupCodeConsumer.call(code: code) == :ok
  end

  def activate_and_redirect
    session_record, plaintext = Pito::Auth::SessionActivator.call(request: request)
    write_session_cookie(plaintext)
    audit("session.login.success",
          session_id: session_record.id,
          ip: request.remote_ip)
    redirect_to root_path
  end

  def mark_failure_and_render_invalid
    request.env["pito.auth_failed"] = true
    SessionThrottle.record_failure(request.remote_ip)
    Pito::Auth::BackoffCalculator.record_trip!(key: ip_backoff_key)

    if SessionThrottle.exhausted?(request.remote_ip)
      render_throttled
      return
    end

    # Z3 (2026-05-25) — auth dialog overlay replaces the /login page. On failure
    # we redirect to root_path with a flash alert so the layout re-renders with
    # the overlay dialog showing the error line. The 422 status previously sent
    # by `render :new` is not needed: the redirect serves a fresh 302 → 200 GET,
    # and the error surfaces via flash[:alert] which the dialog template reads
    # via `Pito::AuthDialogComponent#login_error`.
    flash[:alert] = "login failed."
    redirect_to root_path
  end

  def render_throttled
    audit("session.login.throttled", ip: request.remote_ip)
    response.headers["Retry-After"] = SessionThrottle::WINDOW.to_i.to_s
    render plain: "login failed.",
           status: :too_many_requests
  end

  def ip_backoff_key
    "ip:#{Digest::SHA256.hexdigest(request.remote_ip.to_s)}"
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
end
