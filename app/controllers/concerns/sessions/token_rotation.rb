# Phase 25 — 01g (LD-12 extension). Session token rotation after a
# privileged auth-state mutation.
#
# `LD-12` originally locked rotation on successful 2FA. 01g extends
# the contract to every privileged action that mutates the auth state
# *on the acting session*: approve / block / unblock / purge / TOTP
# enroll / disable / backup-code regenerate. Rotating the token after
# each significantly narrows the window for session fixation against
# a privileged operator.
#
# Usage in a controller after the audit-log write:
#
#     include Sessions::TokenRotation
#     ...
#     def create
#       # ... do the destructive thing, audit log, etc.
#       rotate_session_token!
#       redirect_to ...
#     end
#
# Behavior:
#
#   * Looks up the current session row (`Current.session`). If there
#     is none, no-op — the caller is already on the public path.
#   * Wipes the Rails-managed session bag via `reset_session` so any
#     half-state pre-action does not leak.
#   * Mints a fresh plaintext + digest, stamps the digest on the
#     existing row, and writes the new cookie. The session id, user,
#     and metadata stay the same — only the token bytes rotate.
#
# Safety: never raises. A rotation failure logs and falls through —
# the destructive action already succeeded; failing the response over
# a cookie rewrite would be more confusing than helpful.
module Sessions
  module TokenRotation
    extend ActiveSupport::Concern

    private

    def rotate_session_token!
      session_row = Current.session
      return false if session_row.nil?

      plaintext = SecureRandom.urlsafe_base64(32)
      digest    = Pito::TokenDigest.call(plaintext)
      session_row.update_columns(token_digest: digest)

      reset_session

      cookies.signed[Sessions::Authenticator::COOKIE_NAME] = {
        value: plaintext,
        httponly: true,
        same_site: :lax,
        secure: !Rails.env.test?,
        expires: session_row.remember? ? Session::REMEMBER_ME_TTL.from_now : nil
      }

      true
    rescue StandardError => e
      Rails.logger.warn(
        "[Sessions::TokenRotation] failed: #{e.class}: #{e.message}"
      )
      false
    end
  end
end
