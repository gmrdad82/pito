# Phase 7 — Step A (7a-google-oauth-and-identity.md) — return-path
# helper for the Google OAuth dance.
#
# Two intents flow through the same callback (`/auth/google/callback`):
#   - "youtube_connect" — kicked off by Settings → YouTube; success
#     returns the user to `/settings/youtube`.
#   - nil (sign-in) — Phase 12 owns the user-facing session
#     establishment; Phase 7 leaves a TODO and redirects to root.
#
# The intent is stashed in `session[:google_oauth_intent]` by the
# request-phase entry points (`Settings::YoutubeController#connect`
# is the only producer in Phase 7) and consumed once by the callback
# controller — `session.delete` semantics keep the next callback from
# silently honoring an old intent.
module GoogleOauthRedirect
  extend ActiveSupport::Concern

  SESSION_INTENT_KEY = :google_oauth_intent
  YOUTUBE_CONNECT_INTENT = "youtube_connect"

  private

  def consume_oauth_intent
    session.delete(SESSION_INTENT_KEY)
  end

  def stash_youtube_connect_intent
    session[SESSION_INTENT_KEY] = YOUTUBE_CONNECT_INTENT
  end

  # Resolve the post-callback redirect target for the given intent.
  #
  # `youtube_connect` → `/settings/youtube` (7C surface).
  # nil / unknown   → `root_path` (Phase 12 placeholder; see
  #                    Auth::GoogleCallbacksController for the TODO).
  def redirect_target_for_intent(intent)
    case intent
    when YOUTUBE_CONNECT_INTENT then settings_youtube_path
    else root_path
    end
  end
end
