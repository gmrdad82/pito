require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  Sidekiq::Web.use Rack::Auth::Basic do |username, password|
    expected_user = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :username)
    expected_pass = Rails.application.credentials.dig(:sidekiq, Rails.env.to_sym, :password)

    ActiveSupport::SecurityUtils.secure_compare(username, expected_user.to_s) &
      ActiveSupport::SecurityUtils.secure_compare(password, expected_pass.to_s)
  end
  mount Sidekiq::Web => "/sidekiq"

  root "dashboard#index"

  # JSON-only alias for the dashboard. The pito-sh terminal client expects to
  # GET /dashboard.json (rather than /.json), so we expose a named route that
  # routes to the same controller action.
  get "dashboard", to: "dashboard#index", as: :dashboard

  resources :channels, only: [ :index, :show, :new, :create, :edit, :update, :destroy ] do
    collection do
      get :panes
    end
    member do
      # Nested videos endpoint used by pito-sh: /channels/:id/videos.json
      # returns the videos belonging to the channel as a JSON array.
      get :videos
    end
  end
  resources :videos, only: [ :index, :show, :new, :create, :edit, :update ] do
    collection do
      get :panes
    end
    member do
      # Nested stats endpoint used by pito-sh: /videos/:id/stats.json returns
      # the per-day VideoStat rows for the video as a JSON array.
      get :stats
    end
  end
  # Phase 4 — Project Workspace. Phase A lands the route shells so
  # `projects_path` and friends resolve before Phase B's nav/header edits
  # fire. Controller bodies (other than the importer download stub) are
  # Phase B work.
  resources :projects
  resources :collections
  resources :games
  resources :footages
  resources :notes
  resources :timelines

  # Importer download endpoint — single controller, branches on Rails.env
  # in Phase B. Route shell lands now (§14 step 8 ordering); controller body
  # is part of Phase B's CLI build/distribution workstream.
  get "footage/importer/download",
      to: "footage_importer/downloads#show",
      as: :footage_importer_download

  # Nested JSON API for the importer (Phase B). Route shell only.
  namespace :api do
    resources :projects, only: [] do
      resources :footages, only: [ :index, :create ]
    end
  end

  resources :saved_views, only: [ :index, :create, :destroy ]
  get "deletions/:type/:ids", to: "deletions#show", as: :deletions
  post "deletions/:type/:ids", to: "deletions#create"
  get "syncs/:type/:ids", to: "syncs#show", as: :syncs
  post "syncs/:type/:ids", to: "syncs#create"
  resources :bulk_operations, only: [ :show ] do
    member do
      get :status
    end
  end
  get "search", to: "search#show"
  get "settings", to: "settings#index"
  patch "settings", to: "settings#update"
  patch "settings/theme", to: "settings#update_theme"
  post "settings/reindex", to: "settings#reindex"

  # MCP HTTP transport (served by dedicated Puma on port 3001)
  require_relative "../app/mcp/rack_app"
  mount Mcp::RackApp.new => "/mcp"

  get "up" => "rails/health#show", as: :rails_health_check
end
