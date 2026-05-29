# Cookie-backed session rotation after a privileged auth-state mutation.
#
# After a destructive action (TOTP enroll, backup-code regenerate, ...)
# this concern re-mints the session cookie with a fresh `sid` so any
# captured old cookie is effectively invalidated (different sid).
#
# Does not require a DB lookup — the encrypted cookie is self-validating.
module Sessions
  module TokenRotation
    extend ActiveSupport::Concern

    private

    def rotate_session_token!
      return false unless Current.session

      reset_session

      Current.session = Pito::Auth::SessionCookie.mint!(
        request,
        totp_verified_at: Time.current
      )

      true
    rescue StandardError => e
      Rails.logger.warn(
        "[Sessions::TokenRotation] failed: #{e.class}: #{e.message}"
      )
      false
    end
  end
end
