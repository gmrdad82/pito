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
  get "/chat/:uuid", to: "conversations#show", as: :conversation

  # Dev helper: clears the session cookie so you can re-test /authenticate
  delete "/logout", to: "sessions#destroy", as: :logout

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
