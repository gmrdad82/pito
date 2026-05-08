# Phase 7 — Step A (7a-google-oauth-and-identity.md) — register the
# Google OAuth provider with OmniAuth. State parameter validation is
# the gem default in `omniauth-google-oauth2 >= 1.0`. PKCE is
# requested explicitly — the project's confidential web app client
# stores its secret server-side, but PKCE is a free defense-in-depth.
#
# Two scope sets are configured at the provider level via the
# default `scope:` argument; the request phase overrides this with
# `params[:scope]` for the YouTube-connect surface (see
# `Settings::YoutubeController#connect`).

OmniAuth.config.allowed_request_methods = [ :post, :get ]
OmniAuth.config.silence_get_warning = true

# Surface OmniAuth failure to our own controller rather than the
# default GET-loop. The route is `/auth/failure`; we mount it in
# `config/routes.rb`.
OmniAuth.config.on_failure = proc do |env|
  Auth::GoogleCallbacksController.action(:failure).call(env)
end

# Phase 7.5 — Step 01 hygiene sweep. Three-tier resolver mirroring the
# Phase 5 pepper pattern in `Pito::TokenDigest#pepper`: credentials first,
# then ENV var, then a test-mode placeholder so CI can boot without
# `master.key`. Boot loudly with a clear message if no tier resolves
# rather than letting OmniAuth ride on `nil` and fail mysteriously at
# the `/auth/google` entry point.
google_oauth_credentials = Rails.application.credentials.google_oauth || {}
google_oauth_client_id =
  google_oauth_credentials[:client_id] ||
  ENV["PITO_GOOGLE_OAUTH_CLIENT_ID"] ||
  (Rails.env.test? ? "test-google-oauth-client-id-not-a-secret" : nil)
google_oauth_client_secret =
  google_oauth_credentials[:client_secret] ||
  ENV["PITO_GOOGLE_OAUTH_CLIENT_SECRET"] ||
  (Rails.env.test? ? "test-google-oauth-client-secret-not-a-secret" : nil)

if google_oauth_client_id.blank? || google_oauth_client_secret.blank?
  raise "missing google_oauth credentials: populate :google_oauth.client_id " \
        "and :google_oauth.client_secret via `bin/rails credentials:edit` " \
        "(or set PITO_GOOGLE_OAUTH_CLIENT_ID / PITO_GOOGLE_OAUTH_CLIENT_SECRET)"
end

Rails.application.config.middleware.use OmniAuth::Builder do
  provider :google_oauth2,
           google_oauth_client_id,
           google_oauth_client_secret,
           {
             # Default scope set is the lightweight sign-in profile;
             # `Settings::YoutubeController#connect` overrides via
             # session-stashed params in the request-phase rewrite.
             scope: "openid email profile",
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
               # production we pin to the credentials value (must
               # match the URI registered with the Google Cloud
               # Console). The `:redirect_uri` key is optional (defaults
               # to the production URL) so we keep a fallback string.
               if Rails.env.test?
                 nil
               else
                 google_oauth_credentials[:redirect_uri].presence ||
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
