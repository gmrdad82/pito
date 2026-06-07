# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). Return-path helper for the YouTube-connection
# OAuth dance.
#
# After ADR 0006 the only legitimate intent flowing through
# `/auth/youtube/callback` is `"youtube_connect"`. The dormant sign-in
# branch is gone; a callback without the intent is treated as stale /
# replayed and routed to the failure path.
#
# The intent is stashed in `session[:youtube_connection_oauth_intent]`
# by the chat `/connect` flow (`ChatController#handle_connect` →
# `stash_youtube_connect_intent`) and consumed once by the callback
# controller — `session.delete` semantics keep the next callback from
# silently honoring an old intent.
#
# The post-OAuth redirect returns to the originating conversation (its
# uuid is stashed in the session alongside the intent).
module YoutubeConnectionOauthRedirect
  extend ActiveSupport::Concern

  SESSION_INTENT_KEY           = :youtube_connection_oauth_intent
  SESSION_CONVERSATION_UUID_KEY = :youtube_connect_conversation_uuid
  YOUTUBE_CONNECT_INTENT       = "youtube_connect"

  private

  def consume_oauth_intent
    session.delete(SESSION_INTENT_KEY)
  end

  def stash_youtube_connect_intent
    session[SESSION_INTENT_KEY] = YOUTUBE_CONNECT_INTENT
  end

  def stash_connect_conversation_uuid(uuid)
    session[SESSION_CONVERSATION_UUID_KEY] = uuid
  end

  def consume_connect_conversation_uuid
    session.delete(SESSION_CONVERSATION_UUID_KEY)
  end

  # Resolve the post-callback redirect target for the given intent.
  # For `youtube_connect`: returns the originating /chat/:uuid when a
  # conversation UUID was stashed; falls back to root.
  # Unknown intents → the failure path.
  def redirect_target_for_intent(intent)
    case intent
    when YOUTUBE_CONNECT_INTENT
      uuid = consume_connect_conversation_uuid
      uuid.present? ? conversation_path(uuid: uuid) : root_path
    else
      youtube_connection_oauth_failure_path
    end
  end
end
