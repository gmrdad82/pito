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

  root "start_screens#show"
  post "/chat", to: "chat#create", as: :chat
  post "/autocomplete", to: "autocomplete#create", as: :autocomplete
  get "/chat/:uuid", to: "conversations#show", as: :conversation

  # Dev helper: clears the session cookie so you can re-test /authenticate
  delete "/logout", to: "sessions#destroy", as: :logout

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check

  # Dynamic error pages — rendered by exceptions_app = routes so the 404
  # page shows the full start screen with the autocomplete-enabled chatbox.
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
