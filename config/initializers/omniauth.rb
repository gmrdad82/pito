# Phase 9 — Login-with-Google Drop + GoogleIdentity → YoutubeConnection
# rename (ADR 0006). Google OAuth is now exclusively the YouTube-
# connection dance; the sign-in-with-Google branch is retired.
#
# State parameter validation is the gem default in
# `omniauth-google-oauth2 >= 1.0`. PKCE is requested explicitly — the
# project's confidential web app client stores its secret server-side,
# but PKCE is a free defense-in-depth.
#
# Scope strategy — single set, requested every time. Pito's only Google
# OAuth flow is the YouTube-connection handshake (the sign-in branch was
# retired in ADR 0006). The provider asks for the full YouTube scope
# set on every `/auth/google_oauth2` request so the resulting access
# token can drive every API surface pito uses:
#
#   * `openid email profile`           — user identity in the auth hash
#   * `youtube.readonly`               — channels.list, videos.list,
#                                        playlists.list
#   * `yt-analytics.readonly`          — youtubeAnalytics.reports.query
#   * `youtube.force-ssl`              — videos.update sync-back (Phase
#                                        12), channels.update / banner /
#                                        watermark writes (Phase 11+)
#
# The consent screen surfaces all of them once; subsequent reconnect
# flows use the same set so tokens minted under an earlier (narrower)
# scope set are upgraded the next time the user clicks `[reconnect]`.

OmniAuth.config.allowed_request_methods = [ :post, :get ]
OmniAuth.config.silence_get_warning = true

# Surface OmniAuth failure to our own controller rather than the
# default GET-loop. The route is `/auth/failure`; we mount it in
# `config/routes.rb`.
OmniAuth.config.on_failure = proc do |env|
  YoutubeConnections::OauthCallbacksController.action(:failure).call(env)
end

# Phase 29 — Unit A1. YouTube / Google OAuth credentials moved back
# OUT of the AppSetting singleton and into
# `Rails.application.credentials.google_oauth` (the project's stated
# configuration strategy — secrets live exclusively in credentials).
# Google / YouTube config is now deploy-time config; rotating it
# requires a `bin/rails credentials:edit` + a Puma restart. This
# deliberately closes follow-up 3 (the omniauth hot-rotation gap) by
# accepting the tradeoff rather than chasing per-request resolution.
#
# The resolver is now three-tier:
#
#   1. `Rails.application.credentials.google_oauth` block (primary).
#   2. ENV var (PITO_GOOGLE_OAUTH_CLIENT_ID /
#      PITO_GOOGLE_OAUTH_CLIENT_SECRET) for CI / local-no-DB workflows.
#   3. Test-mode placeholder so request specs boot without
#      `master.key`.

google_oauth_credentials = Rails.application.credentials.google_oauth || {}

google_oauth_client_id =
  google_oauth_credentials[:client_id].presence ||
  ENV["PITO_GOOGLE_OAUTH_CLIENT_ID"].presence ||
  (Rails.env.test? ? "test-google-oauth-client-id-not-a-secret" : nil)

google_oauth_client_secret =
  google_oauth_credentials[:client_secret].presence ||
  ENV["PITO_GOOGLE_OAUTH_CLIENT_SECRET"].presence ||
  (Rails.env.test? ? "test-google-oauth-client-secret-not-a-secret" : nil)

google_oauth_redirect_uri =
  google_oauth_credentials[:redirect_uri].presence

if google_oauth_client_id.blank? || google_oauth_client_secret.blank?
  raise "missing google_oauth credentials: add :google_oauth.client_id " \
        "+ :google_oauth.client_secret via `bin/rails credentials:edit` " \
        "(or set PITO_GOOGLE_OAUTH_CLIENT_ID / " \
        "PITO_GOOGLE_OAUTH_CLIENT_SECRET for CI / local-no-DB workflows)."
end

# Single scope set requested every time — see the scope strategy
# block in the file header. Listed as a constant rather than inlined
# so request specs and callback specs can reference the canonical set
# without duplicating the string.
PITO_GOOGLE_OAUTH_SCOPES = %w[
  openid
  email
  profile
  https://www.googleapis.com/auth/youtube.readonly
  https://www.googleapis.com/auth/yt-analytics.readonly
  https://www.googleapis.com/auth/youtube.force-ssl
].freeze

# Subset of PITO_GOOGLE_OAUTH_SCOPES the controller treats as
# load-bearing for the YouTube surface. Missing any of these in the
# callback's granted-scopes list flips the connection to
# `needs_reauth: true` so the user is prompted to re-consent with the
# full set (Google's consent screen lets the user uncheck individual
# scopes).
PITO_GOOGLE_OAUTH_REQUIRED_YOUTUBE_SCOPES = %w[
  https://www.googleapis.com/auth/youtube.readonly
  https://www.googleapis.com/auth/yt-analytics.readonly
  https://www.googleapis.com/auth/youtube.force-ssl
].freeze

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           google_oauth_client_id,
           google_oauth_client_secret,
           {
             # Full scope set requested every authorization round.
             # `Settings::YoutubeController#connect` only stashes an
             # intent in session — no request-phase scope override.
             scope: PITO_GOOGLE_OAUTH_SCOPES.join(" "),
             access_type: "offline",
             prompt: "consent",
             skip_jwt: true,
             # The Google Cloud Console is registered with the
             # callback URI `https://app.pitomd.com/auth/google/callback`
             # (NOT the gem default `/auth/google_oauth2/callback`).
             # `callback_path` overrides where OmniAuth's middleware
             # listens for the return; `redirect_uri` (when provided)
             # is the absolute URL Google sees in the auth request and
             # must match an entry registered in the OAuth client.
             callback_path: "/auth/google/callback",
             redirect_uri: (
               # In test we let OmniAuth derive the redirect URI
               # from the request host (test_mode never reaches
               # Google so pin-mismatch doesn't apply). In dev /
               # production we pin to the resolved value (must match
               # the URI registered with the Google Cloud Console).
               # The `:google_oauth, :redirect_uri` credential is
               # OPTIONAL — when blank we fall back to the production
               # callback URL.
               if Rails.env.test?
                 nil
               else
                 google_oauth_redirect_uri ||
                   "https://app.pitomd.com/auth/google/callback"
               end
             ),
             # PKCE is free defense-in-depth; the gem requires
             # `provider_ignores_state: false` (the default) for state
             # validation to remain in force.
             pkce: true
           }
end

# Test mode hook — request specs and system specs flip this to
# `true` and stub auth hashes with `OmniAuth.config.add_mock(...)`.
# In production / dev this stays false.
OmniAuth.config.test_mode = false if defined?(OmniAuth.config.test_mode)
