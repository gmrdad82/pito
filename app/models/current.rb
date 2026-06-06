# Per-request global that carries the authenticated identity for a single
# HTTP request or background job. Inherits from ActiveSupport::CurrentAttributes,
# which guarantees all attributes are reset to nil at the end of every request
# (the `around_action :reset_current_after_request` hook in Sessions::AuthConcern
# calls `Current.reset` explicitly for defence-in-depth).
#
# Attribute contract:
#
#   Current.session  — set by Sessions::AuthConcern#authenticate_session! when a
#                      valid, non-expired Pito::Auth::SessionCookie is present.
#                      Holds a Pito::Auth::SessionCookie::SessionData value object
#                      (sid, authenticated, totp_verified_at, created_at,
#                      last_seen_at). Nil for unauthenticated / anonymous requests.
#
#   Current.token    — reserved for future API (Bearer-token) surfaces.  Not yet
#                      populated by any middleware; callers should treat a nil value
#                      as "no API token presented".
#
# The three auth states a caller should handle:
#
#   1. Fully authenticated — Current.session present and #authenticated == true.
#   2. Token auth          — Current.token present (not implemented in Z1).
#   3. Anonymous           — both nil; the request reached an allow_anonymous action.
class Current < ActiveSupport::CurrentAttributes
  # Z1 (2026-05-25) — `user` dropped with the `users` table. pito is
  # single-install; the owner is identified solely by the active session.
  # `token` is kept for API (Bearer) surfaces; `session` is the cookie
  # session pin.
  attribute :session, :token
end
