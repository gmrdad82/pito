Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  # Auth is TOTP-only via the chatbox (`/authenticate <code>`) — no login
  # or logout routes. See ChatController + Pito::Auth::ChatLogin.

  # YouTube OAuth callback (Google OAuth 2.0, YouTube-connection only)
  match "/auth/youtube/callback",
        to: "youtube_connections/oauth_callbacks#create",
        via: %i[get post],
        as: :youtube_connection_oauth_callback
  get "/auth/failure",
      to: "youtube_connections/oauth_callbacks#failure",
      as: :youtube_connection_oauth_failure

  # MCP (G130): read-only Model Context Protocol endpoint (JSON-RPC 2.0), Bearer-
  # authenticated via hand-rolled OAuth. Served by a dedicated Puma container in
  # production; cloudflared routes /mcp, /oauth, /.well-known to it.
  post "/mcp", to: "mcp#handle", as: :mcp

  # OAuth 2.1 (public clients, PKCE) for MCP.
  post "/oauth/register",  to: "oauth#register",  as: :oauth_register
  get  "/oauth/authorize", to: "oauth#authorize", as: :oauth_authorize
  post "/oauth/authorize", to: "oauth#approve"
  post "/oauth/token",     to: "oauth#token",     as: :oauth_token

  # OAuth discovery documents (RFC 8414 / RFC 9728).
  get "/.well-known/oauth-authorization-server", to: "well_known#authorization_server"
  get "/.well-known/oauth-protected-resource",   to: "well_known#protected_resource"

  root "start_screens#show"
  get   "/notifications",     to: "notifications#index",  as: :notifications
  patch "/notifications/:id", to: "notifications#update", as: :notification
  post "/chat", to: "chat#create", as: :chat
  post "/suggestions", to: "suggestions#create", as: :suggestions
  # IGDB game search + import endpoints (used by the /games import sidebar).
  # POST /games/search — query IGDB; returns JSON { hits:, error: }
  # POST /games/import — enqueue GameImportJob; returns 204
  scope "/games", module: "games" do
    post "search",       to: "search#create",       as: :games_search
    post "import",       to: "import#create",        as: :games_import
    post "search-local", to: "search_local#create",  as: :games_search_local
  end
  scope "/videos", module: "videos" do
    post "search-local", to: "search_local#create", as: :videos_search_local
  end
  # Marks a channel-visit event consumed: the pito--auto-visit controller POSTs
  # here after its one-time click so the event flips to its :visited (follow-up)
  # state and never auto-clicks again on refresh.
  post "/channels/visit_consume", to: "channels/visits#consume", as: :channel_visit_consume
  get "/resume", to: "conversations#resume", as: :resume
  get    "/chat/:uuid", to: "conversations#show",    as: :conversation
  patch  "/chat/:uuid", to: "conversations#update"
  delete "/chat/:uuid", to: "conversations#destroy"

  # Settings toggle endpoints — require authentication (no allow_anonymous).
  patch  "/settings/theme",      to: "settings#theme",             as: :settings_theme
  # The /config ai picker dialog's persistence endpoint (key set/clear, model pick).
  patch  "/settings/ai",         to: "settings#ai",                as: :settings_ai

  # JSON login for non-browser clients (pito-tui): POST /session {otp} mints
  # the same encrypted session cookie the chatbox /authenticate flow does.
  post "/session", to: "sessions#create", as: :session

  # The running build's identity — the refresh nudge's reconnect check (G71).
  get "/version", to: "versions#show", as: :version

  # Dev helper: clears the session cookie so you can re-test /authenticate
  delete "/logout", to: "sessions#destroy", as: :logout

  post "/share/:uuid/unfold", to: "shares#unfold", as: :unfold_share
  get "/share/:uuid", to: "shares#show", as: :share

  # Public path-configuration document for the Hotwire Native Android client.
  # No authentication required — the native shell fetches this before any session exists.
  get "/configurations/android_v1", to: "configurations#android_v1",
      as: :android_v1_configuration, defaults: { format: :json }

  # Dynamic error pages — rendered by exceptions_app = routes so the 404
  # page shows the full start screen with the suggestions-enabled chatbox.
  # /404 is the primary path Rails internally redirects to on a routing error.
  # The catch-all at the end handles any path that slips through without
  # raising a RoutingError (e.g. direct navigation to unknown URLs in tests).
  match "/404", to: "start_screens#not_found", via: :all
  match "/422", to: "start_screens#not_found", via: :all
  match "/500", to: "start_screens#not_found", via: :all

  # Catch-all: must be LAST. Excludes /rails/** and /assets/** to avoid
  # interfering with framework internals and the asset pipeline.
  match "*path",
        to: "start_screens#not_found",
        via: :all,
        constraints: ->(req) { !req.path.start_with?("/rails/", "/assets/") }
end
