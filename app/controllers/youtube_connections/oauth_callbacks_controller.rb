# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). Google OAuth callback handler — narrowed to the
# YouTube-connection flow only.
#
# The single endpoint at `/auth/google/callback` (URL fixed by the
# Google Cloud Console registration) handles ONLY the YouTube-connect
# flow (intent = "youtube_connect"; kicked off by Settings → YouTube's
# [ connect ] button). The Phase 7 sign-in branch — a `TODO(phase-12)`
# placeholder that redirected to root — is permanently retired per
# ADR 0006: pito will never offer sign-in-with-Google.
#
# Any callback hitting `/auth/google/callback` without the
# `youtube_connect` intent in session is treated as a stale / replayed
# callback and redirected to the failure path with a generic flash
# explaining that sign-in via Google is not supported.
#
# State parameter validation is OmniAuth's responsibility — the
# `omniauth-google-oauth2` gem turns it on by default and OmniAuth
# rejects mismatched state with `omniauth.error.type = :csrf_detected`
# before this controller runs. We surface that as a clean redirect
# to /auth/failure with a flash.
class YoutubeConnections::OauthCallbacksController < ApplicationController
  include YoutubeConnectionOauthRedirect

  STALE_INTENT_FLASH = "sign-in via Google is not supported. log in with email and password.".freeze

  # Flash copy for the partial-grant sad path. The user reached the
  # Google consent screen and dismissed one or more YouTube scopes;
  # the token we received works for whatever was granted, but pito's
  # YouTube surfaces need the full required set. Tone mirrors the
  # missing-scopes copy in `_needs_reauth_banner.html.erb`.
  PARTIAL_GRANT_FLASH = "Google account connected, but some required " \
                        "scopes were not granted. click [reconnect] " \
                        "and leave every box checked on the Google " \
                        "consent screen.".freeze

  # `failure` is allowed before sign-in (auth flow can fail upstream
  # of any session creation). `create` is NOT allow_anonymous: the
  # YouTube-connect path expects an active session (the user was signed
  # in to pito BEFORE clicking [ connect ]; the cookie stays through
  # the OAuth round-trip because the redirect bounces through the same
  # domain). Z1: Current.user is gone; guard is now Current.session.
  allow_anonymous :failure

  # OmniAuth's middleware does its own state-parameter check before
  # the controller runs; the callback is a server-to-server return
  # from Google so the CSRF token round-trip does not apply.
  skip_before_action :verify_authenticity_token, only: %i[create failure]

  # GET (or POST) /auth/google/callback
  def create
    auth_hash = request.env["omniauth.auth"]
    intent = consume_oauth_intent

    if auth_hash.nil? || request.env["omniauth.error"].present?
      audit("youtube_connection.callback.failed",
            reason: omniauth_failure_reason(request.env["omniauth.error"]))
      return redirect_to(youtube_connection_oauth_failure_path,
                         alert: failure_message(request.env["omniauth.error"]))
    end

    if intent != YOUTUBE_CONNECT_INTENT
      # No sign-in branch exists post-ADR 0006. Any callback without
      # the `youtube_connect` intent is stale / replayed.
      audit("youtube_connection.callback.stale_intent",
            intent: intent.to_s.presence)
      return redirect_to(youtube_connection_oauth_failure_path,
                         alert: STALE_INTENT_FLASH)
    end

    connection = upsert_youtube_connection_for_current_user(auth_hash)
    if connection.nil?
      audit("youtube_connection.callback.failed", reason: "no_active_session")
      return redirect_to(youtube_connection_oauth_failure_path,
                         alert: "session expired. please sign in and retry.")
    end

    missing = missing_required_scopes(connection)
    if missing.any?
      # Partial grant — Google's consent screen lets the user uncheck
      # individual scopes, so a "success" callback can still leave the
      # token unable to drive the YouTube surfaces. Flip needs_reauth
      # back on (the upsert defaulted it false) so the manage page
      # renders the missing-scopes banner copy, and explain in flash.
      connection.update_columns(needs_reauth: true)
      audit("youtube_connection.callback.partial_grant",
            user_id: connection.user_id,
            connection_id: connection.id,
            missing_scopes: missing)
      flash[:alert] = PARTIAL_GRANT_FLASH
      return redirect_to redirect_target_for_intent(intent)
    end

    audit("youtube_connection.callback.succeeded",
          user_id: connection.user_id,
          connection_id: connection.id)

    # Channel discovery — the `[add]` flow on /settings/youtube wants
    # the callback to enumerate the channels visible under this grant
    # and add any non-duplicates as Channel rows under the connection.
    # Duplicates (by UC id) are silently skipped; the flash composes
    # an "already linked" note if EVERY returned channel was already
    # in pito. API failures (quota, transient) surface as a flash but
    # do NOT roll back the connection itself — the user can retry the
    # discovery from /settings/youtube without re-doing OAuth.
    discovery = discover_and_link_channels(connection)
    flash[:notice] = compose_callback_flash(discovery)
    redirect_to redirect_target_for_intent(intent)
  end

  # GET /auth/failure
  def failure
    @reason = params[:message].to_s.presence || "auth_failed"
    flash.now[:alert] ||= "Google sign-in failed (#{@reason})."
    render plain: "Google sign-in failed: #{@reason}", status: :unauthorized
  end

  private

  # Find or create the YoutubeConnection row for `Current.user` keyed
  # on `google_subject_id` (install-wide unique). Returns nil if no
  # current user is in scope (the connect flow expects a logged-in
  # pito user).
  def upsert_youtube_connection_for_current_user(auth_hash)
    # Z1: User model gone; guard on active session instead.
    return nil unless Current.session.present?

    info = auth_hash.respond_to?(:info) ? auth_hash.info : auth_hash["info"] || {}
    creds = auth_hash.respond_to?(:credentials) ? auth_hash.credentials : auth_hash["credentials"] || {}
    extra_raw = auth_hash.respond_to?(:extra) ? auth_hash.extra : auth_hash["extra"] || {}

    subject_id = (auth_hash["uid"] || (auth_hash.respond_to?(:uid) ? auth_hash.uid : nil)).to_s
    granted_scopes = parse_granted_scopes(extra_raw, creds)

    connection = YoutubeConnection.find_or_initialize_by(
      google_subject_id: subject_id
    )
    connection.email              = info["email"] || connection.email
    connection.access_token       = creds["token"]
    connection.refresh_token      = creds["refresh_token"] || connection.refresh_token
    connection.expires_at         = expiry_from_credentials(creds)
    # The current grant is the source of truth — the stored array reflects
    # the scope set actually attached to this access token, not a stale
    # historical union. The post-upsert partial-grant check (see #create)
    # uses this same list to detect missing required scopes.
    connection.scopes             = granted_scopes.uniq
    connection.needs_reauth       = false
    connection.last_authorized_at = Time.current

    connection.save!
    connection
  end

  # Return the subset of PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES that
  # did NOT make it onto this connection's stored scopes array. An
  # empty array means the grant covered everything pito needs; a
  # non-empty array means the user dismissed at least one scope on the
  # Google consent screen and the surface should prompt to reconnect.
  def missing_required_scopes(connection)
    required = Array(PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES)
    granted = Array(connection.scopes)
    required - granted
  end

  # Build the granted-scope list from the auth hash. OmniAuth
  # surfaces it under `extra.raw_info.scope` (space-joined string)
  # OR `credentials.scope` (also space-joined). Walk both spots.
  def parse_granted_scopes(extra, creds)
    raw = nil
    if extra.respond_to?(:[])
      raw_info = extra["raw_info"] || (extra.respond_to?(:raw_info) ? extra.raw_info : nil)
      raw = (raw_info && (raw_info["scope"] || raw_info[:scope])) ||
            extra["scope"]
    end
    raw ||= creds["scope"] if creds.respond_to?(:[])
    raw.to_s.split.reject(&:blank?)
  end

  # Google returns `expires_at` (Unix epoch). Some flows return
  # `expires_in` instead. Prefer `expires_at`; fall back to
  # `expires_in` plus now.
  def expiry_from_credentials(creds)
    if (epoch = creds["expires_at"]).present?
      Time.at(epoch.to_i).utc
    elsif (in_seconds = creds["expires_in"]).present?
      in_seconds.to_i.seconds.from_now
    else
      1.hour.from_now
    end
  end

  def failure_message(error)
    return "auth_failed" if error.nil?

    case error
    when ::OAuth2::Error then "auth_failed"
    else error.try(:message) || error.try(:type) || "auth_failed"
    end
  end

  def omniauth_failure_reason(error)
    return "missing_auth_hash" if error.nil?

    error.try(:type) || error.class.name
  end

  # Enumerate `mine: true` channels for the just-authorized connection
  # and add any that are not already linked. Returns a stable Hash
  # shape used by `compose_callback_flash`:
  #
  #   { added: [titles…], duplicates: [titles…], error: nil | "quota exceeded" | … }
  #
  # Duplicate detection is keyed on the UC channel URL
  # (`https://www.youtube.com/channel/<UC id>`) — the existing
  # `channel_url` UNIQUE index in the DB is the source of truth for
  # "this channel is already linked to pito". A duplicate match that
  # points at a different YoutubeConnection (or has a nil connection)
  # is still treated as duplicate — re-attaching it via the callback
  # would silently steal it out of the user's other connection,
  # which is not a "discovery" behavior the user expects from `[add]`.
  #
  # Errors surfacing from the YouTube client (quota, transient, needs
  # reauth) are caught here so the OAuth-success redirect still
  # completes; the manage page will show the connection but no new
  # channels until the user retries.
  def discover_and_link_channels(connection)
    items = []
    begin
      response = Channel::Youtube::Client.new(connection).channels_list(
        mine: true, parts: %i[snippet statistics]
      )
      items = Array(response[:items])
    rescue Channel::Youtube::QuotaExhaustedError
      audit("youtube_connection.callback.discovery_failed",
            connection_id: connection.id, reason: "quota_exhausted")
      return { added: [], duplicates: [], error: "quota exceeded" }
    rescue Channel::Youtube::NeedsReauthError
      audit("youtube_connection.callback.discovery_failed",
            connection_id: connection.id, reason: "needs_reauth")
      return { added: [], duplicates: [], error: "needs reauth" }
    rescue Channel::Youtube::TransientError
      audit("youtube_connection.callback.discovery_failed",
            connection_id: connection.id, reason: "transient")
      return { added: [], duplicates: [], error: "service temporarily unavailable" }
    end

    added = []
    duplicates = []

    items.each do |item|
      uc_id = item[:id].to_s
      next if uc_id.blank?

      title = item.dig(:snippet, :title).to_s
      channel_url = "https://www.youtube.com/channel/#{uc_id}"

      existing = Channel.find_by(channel_url: channel_url)
      if existing
        duplicates << title.presence || uc_id
        next
      end

      Channel.create!(
        channel_url: channel_url,
        youtube_connection_id: connection.id,
        last_synced_at: Time.current
      )
      added << (title.presence || uc_id)
    end

    audit("youtube_connection.callback.discovery_succeeded",
          connection_id: connection.id,
          added_count: added.length,
          duplicate_count: duplicates.length)
    { added: added, duplicates: duplicates, error: nil }
  end

  # Compose the user-visible flash from a `discover_and_link_channels`
  # result. The copy reads as a continuation of "Google account
  # connected." — concise, one short sentence per outcome bucket.
  #
  # Output examples (the discovery hash drives which line appears):
  #
  #   { added: [], duplicates: [] }
  #     → "Google account connected. no channels found under this Google account."
  #   { added: ["Alpha"], duplicates: [] }
  #     → "Google account connected. 1 channel added (Alpha)."
  #   { added: ["Alpha", "Beta"], duplicates: [] }
  #     → "Google account connected. 2 channels added (Alpha, Beta)."
  #   { added: [], duplicates: ["Alpha"] }
  #     → "Google account connected. channel 'Alpha' is already linked."
  #   { added: [], duplicates: ["Alpha", "Beta"] }
  #     → "Google account connected. these channels are already linked: Alpha, Beta."
  #   { added: ["Alpha"], duplicates: ["Beta"] }
  #     → "Google account connected. 1 channel added (Alpha). channel 'Beta' is already linked."
  #   { added: [], duplicates: [], error: "quota exceeded" }
  #     → "Google account connected. couldn't list channels right now (quota exceeded). open /channels and click [+] to retry."
  def compose_callback_flash(discovery)
    parts = [ "Google account connected." ]

    if discovery[:error].present?
      parts << "couldn't list channels right now (#{discovery[:error]}). open /channels and click [+] to retry."
      return parts.join(" ")
    end

    added = Array(discovery[:added])
    duplicates = Array(discovery[:duplicates])

    if added.any?
      noun = added.length == 1 ? "channel" : "channels"
      parts << "#{added.length} #{noun} added (#{added.join(', ')})."
    end

    if duplicates.length == 1
      parts << "channel '#{duplicates.first}' is already linked."
    elsif duplicates.length > 1
      parts << "these channels are already linked: #{duplicates.join(', ')}."
    end

    if added.empty? && duplicates.empty?
      parts << "no channels found under this Google account."
    end

    parts.join(" ")
  end

  # Phase 9 — audit trail for callback outcomes. Mirrors the helper
  # pattern in `SessionsController#audit` (one structured JSON line
  # per event via the AUTH_AUDIT_LOGGER), gated on the logger being
  # defined. Audit-row keys are locked in
  # `docs/plans/beta/09-login-with-google-drop/specs/01-google-identity-rename.md`
  # under "Master agent decisions → Copy decisions §5".
  def audit(event, **payload)
    return unless defined?(AUTH_AUDIT_LOGGER)

    AUTH_AUDIT_LOGGER.info({
      ts: Time.now.utc.iso8601(3),
      event: event
    }.merge(payload).to_json)
  rescue StandardError
    nil
  end
end
