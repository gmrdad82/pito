require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  # Sidekiq dashboard — basic auth from Rails credentials
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    expected_user = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :username)
    expected_pass = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :password)
    ActiveSupport::SecurityUtils.secure_compare(username, expected_user.to_s) &
      ActiveSupport::SecurityUtils.secure_compare(password, expected_pass.to_s)
  end
  mount Sidekiq::Web => "/sidekiq"

  # OAuth authorization server metadata (RFC 8414)
  get "/.well-known/oauth-authorization-server",
      to: "well_known#oauth_authorization_server",
      as: :oauth_authorization_server_metadata,
      defaults: { format: "json" }

  # Auth — TOTP login
  get  "/login",    to: "sessions#new",     as: :login
  post "/login",   to: "sessions#create"
  delete "/session", to: "sessions#destroy", as: :session_logout

  # Doorkeeper OAuth
  use_doorkeeper do
    skip_controllers :applications, :authorized_applications
  end
  post "/oauth/register", to: "oauth/registrations#create",
       as: :oauth_register, defaults: { format: "json" }

  # Google OAuth callback (YouTube connection)
  match "/auth/google/callback",
        to: "youtube_connections/oauth_callbacks#create",
        via: %i[get post],
        as: :youtube_connection_oauth_callback
  get "/auth/failure",
      to: "youtube_connections/oauth_callbacks#failure",
      as: :youtube_connection_oauth_failure

  root "dashboard#index"

  # JSON-only dashboard alias for pito CLI
  get "dashboard", to: "dashboard#index", as: :dashboard
  get "sidebar", to: "dashboard#sidebar", as: :sidebar
  get "status", to: "dashboard#status", as: :status

  # Commands — slash-command API for xterm.js + Rust TUI
  post "commands/execute", to: "commands#execute"

  # Channels — JSON API surface
  resources :channels, only: [ :index, :show, :destroy ] do
    collection do
      post :connect_google
    end
    member do
      get  :revoke, to: "channel_revokes#show",   as: :revoke
      post :revoke, to: "channel_revokes#create"
      get  :videos  # /channels/:id/videos.json
      resource :star, only: :update, controller: "channels/stars", as: :channel_star
    end
    resource :analytics, only: :show, controller: "channels/analytics"
    post "analytics/refresh", to: "channels/analytics_refresh#create", as: :analytics_refresh
    resources :change_logs, only: :index, path: "history", controller: "channels/change_logs"
  end

  # Bulk channel revoke
  get  "/channels/revokes/:ids", to: "channels/bulk_revokes#show",
       as: :channels_bulk_revoke, constraints: { ids: %r{[\d,]+} }
  post "/channels/revokes/:ids", to: "channels/bulk_revokes#create",
       constraints: { ids: %r{[\d,]+} }

  # Videos — JSON API surface
  resources :videos, only: [ :show, :destroy ] do
    member do
      get :stats
      get   :pre_publish_checklist
      patch :publish
      patch :schedule
      patch :unpublish
      get   :diff
      patch :apply_diff
    end
    resources :links, only: %i[create update destroy], controller: "video_game_links"
    resource :analytics, only: :show, controller: "videos/analytics"
    post "analytics/refresh", to: "videos/analytics_refresh#create", as: :analytics_refresh
    post "analytics/retention/refresh", to: "videos/retention_refresh#create", as: :retention_refresh
  end

  # Games — JSON API surface
  resources :games, only: [ :show, :create, :destroy ] do
    collection do
      get :search
      get :omnisearch
      get :version_parent_search
    end
    member do
      post :resync
    end
  end

  # Footage — JSON API + frame endpoints for scrub UI
  resources :footages, only: [ :index, :show, :edit, :update, :destroy ]
  get "/footages/:id/frames.json",       to: "footages#frames",       as: :footage_frames,       defaults: { format: "json" }
  get "/footages/:footage_id/frames/m/:filename.jpg", to: "footages#frame_master",
      as: :footage_frame_master, constraints: { filename: /\d{2}-\d{2}-\d{2}/ }, defaults: { format: "jpg" }
  get "/footages/:footage_id/frames/t/:filename.jpg", to: "footages#frame_thumb",
      as: :footage_frame_thumb, constraints: { filename: /\d{2}-\d{2}-\d{2}/ }, defaults: { format: "jpg" }
  get "footage/importer/download", to: "footage_importer/downloads#show", as: :footage_importer_download

  # API namespace (bearer auth for importer)
  namespace :api do
    resources :footages, only: [ :index, :create, :update, :destroy ] do
      member do
        patch :frames, action: :update_frames
      end
    end
  end

  # Analytics
  resource :analytics, only: :show, controller: "analytics"

  # Video imports
  namespace :imports do
    resources :channels, only: %i[index create show update]
  end

  # Saved views
  resources :saved_views, only: [ :index, :create, :destroy ]

  # Notifications — JSON API surface
  resources :notifications, only: %i[index show] do
    member do
      patch :read
      patch :unread
    end
    collection do
      patch :mark_read
      patch :mark_all_read
      get   :badge
    end
  end

  # Notifications feed (in-app actions)
  resources :notifications_feed, only: [] do
    collection do
      post :mark_read
      post :mark_unread
    end
  end

  # Calendar — entry CRUD
  scope "/calendar" do
    resources :entries,
              controller: "calendar/entries",
              as: :calendar_entries,
              only: %i[new create show edit update] do
      collection do
        get :quick_add
      end
      member do
        patch :note
        get   :details_pane
      end
    end
  end

  # Deletions — bulk delete confirmation
  get  "deletions/:type/:ids", to: "deletions#show", as: :deletions
  post "deletions/:type/:ids", to: "deletions#create"
  delete "deletions/calendar_entry/:ids",
         to: "deletions#cancel_calendar_entry",
         defaults: { type: "calendar_entry" },
         as: :calendar_entry_cancellation
  delete "deletions/youtube_connection/:ids",
         to: "deletions#destroy_youtube_connection",
         as: :youtube_connection_disconnect

  # Sync toggle
  post "sync/toggle", to: "sync#toggle", as: :sync_toggle

  # Health check
  get "up" => "rails/health#show", as: :rails_health_check
end
