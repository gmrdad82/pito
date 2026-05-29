# Encrypted-cookie TOTP gate for sensitive write actions.
#
# When `AppSetting.totp_enabled?` is true, sensitive write actions
# check `Current.session.totp_verified_at` — if recent enough the
# gate passes without re-entering the code. Otherwise the user must
# supply a fresh 6-digit code on the form.
#
# The 15-minute window avoids annoying re-prompting for rapid edits
# while still requiring a fresh TOTP after a gap. On successful
# verification the cookie's `totp_verified_at` is updated.
#
# Pattern:
#
#   class Settings::FooController < ApplicationController
#     include RecentTotpVerification
#
#     def update
#       return unless require_recent_totp_if_enabled!
#       # ...write path...
#     end
#   end
#
# `require_recent_totp_if_enabled!` returns `true` when:
#   - TOTP is not enrolled, OR
#   - `totp_verified_at` on the session cookie is < 15 min old, OR
#   - the submitted code verifies.
# It returns `false` after rendering / redirecting so the caller MUST
# short-circuit on `false`.
#
# Failure copy is intentionally generic — `credentials don't match.`
module RecentTotpVerification
  extend ActiveSupport::Concern

  GENERIC_FLASH = "credentials don't match."
  TOTP_FRESH_WINDOW = 15.minutes

  private

  def require_recent_totp_if_enabled!(redirect_on_failure: nil, render_action: nil)
    return true unless AppSetting.totp_enabled?

    if totp_recently_verified?
      return true
    end

    code = params[:totp_code].to_s.strip
    if Pito::Auth::TotpVerifier.call(code: code) == :ok
      cookie_manager = Pito::Auth::SessionCookie.new(request)
      Current.session = cookie_manager.mark_totp_verified!(Current.session, at: Time.current)
      return true
    end

    if redirect_on_failure
      redirect_to redirect_on_failure, alert: GENERIC_FLASH
    else
      flash.now[:alert] = GENERIC_FLASH
      if render_action
        render render_action, status: :unprocessable_content
      else
        render :show, status: :unprocessable_content
      end
    end
    false
  end

  def totp_recently_verified?
    session_data = Current.session
    return false unless session_data&.totp_verified_at

    session_data.totp_verified_at > TOTP_FRESH_WINDOW.ago
  end
end
