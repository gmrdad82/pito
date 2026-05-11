# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). Settings → YouTube surface — list the user's
# YoutubeConnection rows (or empty state), render a connect button,
# and surface every Channel currently linked to those connections.
#
# Multi-connection (2026-05-10): the schema already allowed
# `User has_many :youtube_connections` and `google_subject_id` is
# install-wide unique, so multiple rows can coexist. The page renders
# one section per connection owned by `Current.user`. The `[add]`
# button below each section kicks the OmniAuth dance with
# `prompt=select_account` so Google shows the account picker /
# Brand-Account switcher rather than silently reusing the most-recent
# grant. The OAuth callback (see
# `YoutubeConnections::OauthCallbacksController#create`) does the
# channel-discovery work: it enumerates `mine: true` channels via
# `Youtube::Client#channels_list` and adds any non-duplicates as
# Channel rows under the matching YoutubeConnection.
#
# Disconnect runs through the existing action-confirmation page
# framework (`shared/_action_screen.html.erb` +
# `DeletionsController#show_youtube_connection` /
# `#destroy_youtube_connection`). Bulk-as-foundation: a single
# checkbox selection is `/deletions/youtube_connection/<id>`; N
# selections is `/deletions/youtube_connection/<id1>,<id2>,…`.
class Settings::YoutubeController < ApplicationController
  include YoutubeConnectionOauthRedirect

  # GET /settings/youtube
  def show
    @youtube_connections = load_youtube_connections
    # Back-compat alias — the settings index card + the
    # `_needs_reauth_banner` partial reach for `@youtube_connection`
    # (singular). When the user has any connection at all, expose the
    # most recently authorized one so existing surfaces keep working.
    @youtube_connection = @youtube_connections.first

    render :show
  end

  # POST /settings/youtube/connect — entry point for OmniAuth's
  # request phase. Stash the intent so the callback can route the
  # response back to /settings/youtube.
  #
  # `params[:account] == "new"` (the default for the `[add]` /
  # `[+ connect another Google account]` buttons) appends
  # `prompt=select_account` so Google renders the account picker /
  # Brand-Account switcher rather than silently reusing the most
  # recently used Google account. `include_granted_scopes=true`
  # keeps the consent screen additive so an existing grant on the
  # picked account is not downgraded. The omniauth-google-oauth2 gem
  # treats `AUTHORIZE_OPTIONS` as request-overridable — passing those
  # keys in the query string flows them straight into the auth URL.
  def connect
    stash_youtube_connect_intent
    target = if params[:account].to_s == "new"
               "/auth/google_oauth2?" \
                 "prompt=#{ERB::Util.url_encode('select_account consent')}" \
                 "&include_granted_scopes=true"
    else
               "/auth/google_oauth2"
    end
    redirect_to target, allow_other_host: false, status: :see_other
  end

  private

  # Ordered list of every YoutubeConnection owned by the current
  # user. `[]` when no user is signed in (the surface still has to
  # render the empty state without 500ing on the layout).
  def load_youtube_connections
    return [] unless Current.user.present?

    YoutubeConnection
      .where(user_id: Current.user.id)
      .order(last_authorized_at: :desc)
      .to_a
  end
end
