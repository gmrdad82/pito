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

  STALE_INTENT_FLASH = "sign-in via google is not supported. log in with email and password.".freeze

  # `failure` is allowed before sign-in (auth flow can fail upstream
  # of any session creation). `create` is NOT allow_anonymous: the
  # YouTube-connect path expects `Current.user` to be set (the user
  # was signed in to pito BEFORE clicking [ connect ]; the cookie
  # stays through the OAuth round-trip because the redirect bounces
  # through the same domain).
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
      audit("youtube_connection.callback.failed", reason: "no_current_user")
      return redirect_to(youtube_connection_oauth_failure_path,
                         alert: "session expired. please sign in and retry.")
    end

    audit("youtube_connection.callback.succeeded",
          user_id: connection.user_id,
          connection_id: connection.id)
    flash[:notice] = "google account connected."
    redirect_to redirect_target_for_intent(intent)
  end

  # GET /auth/failure
  def failure
    @reason = params[:message].to_s.presence || "auth_failed"
    flash.now[:alert] ||= "google sign-in failed (#{@reason})."
    render plain: "google sign-in failed: #{@reason}", status: :unauthorized
  end

  private

  # Find or create the YoutubeConnection row for `Current.user` keyed
  # on `google_subject_id` (install-wide unique). Returns nil if no
  # current user is in scope (the connect flow expects a logged-in
  # pito user).
  def upsert_youtube_connection_for_current_user(auth_hash)
    return nil unless Current.user.present?

    info = auth_hash.respond_to?(:info) ? auth_hash.info : auth_hash["info"] || {}
    creds = auth_hash.respond_to?(:credentials) ? auth_hash.credentials : auth_hash["credentials"] || {}
    extra_raw = auth_hash.respond_to?(:extra) ? auth_hash.extra : auth_hash["extra"] || {}

    subject_id = (auth_hash["uid"] || (auth_hash.respond_to?(:uid) ? auth_hash.uid : nil)).to_s
    granted_scopes = parse_granted_scopes(extra_raw, creds)

    connection = YoutubeConnection.find_or_initialize_by(
      google_subject_id: subject_id
    )

    connection.user             ||= Current.user
    connection.email              = info["email"] || connection.email
    connection.access_token       = creds["token"]
    connection.refresh_token      = creds["refresh_token"] || connection.refresh_token
    connection.expires_at         = expiry_from_credentials(creds)
    connection.scopes             = (Array(connection.scopes) + granted_scopes).uniq
    connection.needs_reauth       = false
    connection.last_authorized_at = Time.current

    connection.save!
    connection
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
