# frozen_string_literal: true

class SessionsController < ApplicationController
  allow_anonymous :create, :destroy

  # POST /session {otp} — the JSON login for non-browser clients (pito-tui).
  # Reuses the chatbox flow verbatim: Pito::Auth::ChatLogin verifies the TOTP
  # (per-IP throttle included) and mints the SAME encrypted session cookie the
  # web uses — the client keeps a cookie jar and presents it on every request
  # and on the cable handshake. There are NO passwords here: TOTP-only, the
  # same contract as /authenticate in the chatbox.
  def create
    result = Pito::Auth::ChatLogin.call(code: params[:otp].to_s, request: request)

    if result.authenticated?
      Current.session = result.session_data
      render json: { authenticated: true }, status: :created
    else
      render json: {
        authenticated: false,
        error:         result.status,
        message:       auth_error_message(result.status)
      }, status: :unauthorized
    end
  end

  def destroy
    Pito::Auth::SessionCookie.new(request).clear!
    respond_to do |format|
      format.html { redirect_to root_path }
      format.json { head :no_content }
    end
  end

  private

  # Mirrors ChatController#auth_error_key: returns already-resolved copy text
  # (the client prints it verbatim), not an i18n key.
  def auth_error_message(status)
    case status
    when :throttled    then Pito::Copy.render("pito.copy.auth.throttles")
    when :not_enrolled then Pito::Copy.render("pito.copy.auth.not_enrolled")
    else                    Pito::Copy.render("pito.copy.auth.failures")
    end
  end
end
