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

# YouTube / Google OAuth credentials are sourced from AppSetting via
# Pito::Credentials (Rails.cache-backed, 5-min TTL). Set credentials
# with `/config google client_id=… client_secret=… redirect_uri=…`.
#
# The provider is always registered. Credentials are injected per-request
# via OmniAuth's `setup` lambda so the initializer doesn't need Zeitwerk
# autoloading to be active (constants in app/ aren't available until after
# initializers run). Pito::Credentials IS available at request time.
#
# If credentials are blank the OAuth request phase will fail — guard
# against this in ChatController by checking
# `Pito::Credentials.google_oauth_configured?` before initiating the flow.
#
# In test mode Pito::Credentials falls back to hardcoded placeholder strings
# so the spec suite boots without a real AppSetting row.

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
           nil,
           nil,
           {
             scope: PITO_GOOGLE_OAUTH_SCOPES.join(" "),
             access_type: "offline",
             prompt: "consent",
             skip_jwt: true,
             # The Google Cloud Console is registered with the
             # callback URI `<host>/auth/google/callback`
             # (NOT the gem default `/auth/google_oauth2/callback`).
             callback_path: "/auth/google/callback",
             pkce: true,
             # Inject credentials per-request from AppSetting (via
             # Pito::Credentials cache). redirect_uri falls back to
             # the local dev default when blank.
             setup: lambda { |env|
               creds = Pito::Credentials
               env["omniauth.strategy"].options[:client_id]     = creds.google_oauth_client_id
               env["omniauth.strategy"].options[:client_secret] = creds.google_oauth_client_secret
               unless Rails.env.test?
                 env["omniauth.strategy"].options[:redirect_uri] =
                   creds.google_oauth_redirect_uri ||
                   "http://localhost:3027/auth/google/callback"
               end
             }
           }
end

# Test mode hook — request specs and system specs flip this to
# `true` and stub auth hashes with `OmniAuth.config.add_mock(...)`.
# In production / dev this stays false.
OmniAuth.config.test_mode = false if defined?(OmniAuth.config.test_mode)
