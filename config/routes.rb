Rails.application.routes.draw do
  mount ActionCable.server => "/cable"

  # Auth is TOTP-only via the chatbox (`/authenticate <code>`) — no login
  # or logout routes. See ChatController + Pito::Auth::ChatLogin.

  # Google OAuth callback (YouTube connection)
  match "/auth/google/callback",
        to: "youtube_connections/oauth_callbacks#create",
        via: %i[get post],
        as: :youtube_connection_oauth_callback
  get "/auth/failure",
      to: "youtube_connections/oauth_callbacks#failure",
      as: :youtube_connection_oauth_failure

  root "start_screens#show"
  post "/chat", to: "chat#create", as: :chat
  get "/chat/:uuid", to: "conversations#show", as: :conversation

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
