# 2026-05-11 — Fresh-TOTP gate for sensitive write actions.
#
# When `Current.user.totp_enabled?` is true, sensitive destructive
# write actions require a fresh 6-digit TOTP code on the same form.
# Read-only views are NOT gated — only the writes.
#
# 2026-05-16 — scope narrowed. The only surviving gated surface is
# `Settings::UserController#update` (the /settings Row 1 Left
# profile pane's `[ update ]` button — username + password change).
# The previously-gated webhook surfaces (Slack / Discord) lost the
# gate; webhook saves are plain saves now.
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
# `require_recent_totp_if_enabled!` returns `true` when the user has
# no 2FA enabled OR when the submitted code verifies. It returns
# `false` after rendering / redirecting with a generic flash, so the
# caller MUST short-circuit on `false`.
#
# Failure copy is intentionally generic — `credentials don't match.`
# — and the response must not reveal whether the password / code /
# both was the failing field on flows that bundle multiple
# credentials.
#
# Internal use of `Pito::Auth::TotpVerifier` triggers the replay-defense
# watermark on success — a code consumed by a write here cannot be
# replayed against a different sensitive action in the same drift
# window. That is the locked, install-wide replay contract (RFC 6238
# §5.2 — see `Pito::Auth::TotpVerifier` header comment).
module RecentTotpVerification
  extend ActiveSupport::Concern

  GENERIC_FLASH = "credentials don't match."

  private

  # Returns `true` when the gate is satisfied (user has no 2FA OR the
  # submitted code verifies). Returns `false` after rendering or
  # redirecting; the caller MUST short-circuit on `false`.
  #
  # @param redirect_on_failure [Symbol, String, nil] when present,
  #   render is bypassed in favor of `redirect_to`. Useful for
  #   flow-style controllers (e.g. webhook panes) that PATCH and
  #   redirect back to /settings.
  def require_recent_totp_if_enabled!(redirect_on_failure: nil, render_action: nil)
    return true unless Current.user&.totp_enabled?

    code = params[:totp_code].to_s.strip
    return true if Pito::Auth::TotpVerifier.call(user: Current.user, code: code) == :ok

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
end
