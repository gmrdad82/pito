# Phase 7 — Step A (7a-google-oauth-and-identity.md) — Google OAuth
# callback handler.
#
# The single endpoint at `/auth/google/callback` handles BOTH flows:
#   - the YouTube-connect flow (intent = "youtube_connect"; kicked
#     off by Settings → YouTube's [ connect google account ] button)
#   - the sign-in flow (intent = nil; Phase 12 will surface this in
#     the login UI; Phase 7 leaves a TODO and redirects to root_path)
#
# State parameter validation is OmniAuth's responsibility — the
# `omniauth-google-oauth2` gem turns it on by default and OmniAuth
# rejects mismatched state with `omniauth.error.type = :csrf_detected`
# before this controller runs. We surface that as a clean redirect
# to /auth/failure with a flash.
class Auth::GoogleCallbacksController < ApplicationController
  include GoogleOauthRedirect

  # `failure` is allowed before sign-in (auth flow can fail upstream
  # of any session creation). `create` is NOT allow_anonymous: the
  # YouTube-connect path expects `Current.user` to be set (the user
  # was signed in to Pito BEFORE clicking "[ connect google account ]";
  # the cookie stays through the OAuth round-trip because the
  # redirect bounces through the same domain).
  #
  # The Phase 12 sign-in flow will graduate `create` to allow_anonymous
  # OR introduce a separate sign-in callback action; for Phase 7 the
  # sign-in branch is a placeholder TODO and can keep authenticated
  # access (development testing still works because the dev environment
  # always has a live session).
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
      return redirect_to(google_oauth_failure_path,
                         alert: failure_message(request.env["omniauth.error"]))
    end

    # Phase 7's sign-in branch needs Current.user, which the cookie
    # session establishes. Until Phase 12 wires Sign-in-with-Google
    # into the login surface, the YouTube-connect flow is the only
    # supported path; sign-in flow leaves the persistence step out
    # and falls through to the redirect placeholder.
    if intent == YOUTUBE_CONNECT_INTENT
      identity = upsert_identity_for_current_user(auth_hash)
      return redirect_to(google_oauth_failure_path,
                         alert: "session expired. please sign in and retry.") if identity.nil?

      flash[:notice] = "google account connected."
      redirect_to redirect_target_for_intent(intent)
    else
      # TODO(phase-12): real sign-in. Resolve or create the User
      # tied to the google_subject_id, mint a Session, and set the
      # pito_session cookie. For Phase 7 we leave the sign-in
      # surface dormant and redirect to root.
      redirect_to root_path
    end
  end

  # GET /auth/failure
  def failure
    @reason = params[:message].to_s.presence || "auth_failed"
    flash.now[:alert] ||= "google sign-in failed (#{@reason})."
    render plain: "google sign-in failed: #{@reason}", status: :unauthorized
  end

  private

  # Find or create the GoogleIdentity row for `Current.user` keyed
  # on `google_subject_id` (Phase 8 — tenant drop; subject IDs are
  # globally unique). Returns nil if no current user is in scope (the
  # connect flow expects a logged-in Pito user; OAuth without a Pito
  # session is the Phase 12 surface).
  def upsert_identity_for_current_user(auth_hash)
    return nil unless Current.user.present?

    info = auth_hash.respond_to?(:info) ? auth_hash.info : auth_hash["info"] || {}
    creds = auth_hash.respond_to?(:credentials) ? auth_hash.credentials : auth_hash["credentials"] || {}
    extra_raw = auth_hash.respond_to?(:extra) ? auth_hash.extra : auth_hash["extra"] || {}

    subject_id = (auth_hash["uid"] || (auth_hash.respond_to?(:uid) ? auth_hash.uid : nil)).to_s
    granted_scopes = parse_granted_scopes(extra_raw, creds)

    identity = GoogleIdentity.find_or_initialize_by(
      google_subject_id: subject_id
    )

    identity.user           ||= Current.user
    identity.email            = info["email"] || identity.email
    identity.access_token     = creds["token"]
    identity.refresh_token    = creds["refresh_token"] || identity.refresh_token
    identity.expires_at       = expiry_from_credentials(creds)
    identity.scopes           = (Array(identity.scopes) + granted_scopes).uniq
    identity.needs_reauth     = false
    identity.last_authorized_at = Time.current

    identity.save!
    identity
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
end
