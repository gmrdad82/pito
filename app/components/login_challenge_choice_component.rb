# Phase 25 — 01b (LD-17). Two-button choice surface on `/login/challenge`.
#
# Renders the two bracketed-link options the user picks between:
#
#   - `[enter 2FA code]` — submits a hidden form with `challenge_path:
#     totp`. The receiving controller redirects to the TOTP form
#     (`/login/totp`); the real surface lands in `01e`.
#   - `[ask for approval]` — submits `challenge_path: approval`. The
#     receiving controller creates the pending session via
#     `Auth::SessionPendingApprover` and redirects to `/login/pending`.
#
# The component carries no per-user state — it's a pure layout
# primitive. The wrapping page reads the pre-auth marker.
class LoginChallengeChoiceComponent < ViewComponent::Base
  TOTP_LABEL     = "enter 2FA code"
  APPROVAL_LABEL = "ask for approval"

  TOTP_PATH      = "totp"
  APPROVAL_PATH  = "approval"
end
