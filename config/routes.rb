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

  resources :channels, only: [ :index, :show, :new, :create, :edit, :update ] do
    collection do
      get :panes
    end
  end
  resources :videos, only: [ :index, :show, :new, :create, :edit, :update ] do
    collection do
      get :panes
    end
  end
  resources :saved_views, only: [ :create, :destroy ]
  get "deletions/:type/:ids", to: "deletions#show", as: :deletions
  post "deletions/:type/:ids", to: "deletions#create"
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

  get "up" => "rails/health#show", as: :rails_health_check
end
