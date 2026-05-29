# Z2d (2026-05-25) — Fresh-TOTP gate for sensitive write actions.
#
# When `AppSetting.totp_enabled?` is true, sensitive destructive write
# actions require a fresh 6-digit TOTP code on the same form.
# Read-only views are NOT gated — only the writes.
#
# Post-Z1: there is no User model and no Current.user. The gate
# delegates to AppSetting (install-wide TOTP state) instead of the
# per-user row.
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
# `require_recent_totp_if_enabled!` returns `true` when TOTP is not
# enrolled OR when the submitted code verifies. It returns `false`
# after rendering / redirecting with a generic flash, so the caller
# MUST short-circuit on `false`.
#
# Failure copy is intentionally generic — `credentials don't match.`
# — so the response never reveals which field failed.
#
# Internal use of `Pito::Auth::TotpVerifier` triggers the replay-defense
# watermark on success — a code consumed by a write here cannot be
# replayed in the same drift window (RFC 6238 §5.2).
module RecentTotpVerification
  extend ActiveSupport::Concern

  GENERIC_FLASH = "credentials don't match."

  private

  # Returns `true` when the gate is satisfied (TOTP not enrolled OR the
  # submitted code verifies). Returns `false` after rendering or
  # redirecting; the caller MUST short-circuit on `false`.
  #
  # @param redirect_on_failure [Symbol, String, nil] when present,
  #   render is bypassed in favor of `redirect_to`.
  def require_recent_totp_if_enabled!(redirect_on_failure: nil, render_action: nil)
    return true unless AppSetting.totp_enabled?

    code = params[:totp_code].to_s.strip
    return true if Pito::Auth::TotpVerifier.call(code: code) == :ok

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
