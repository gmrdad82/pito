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

  resources :channels, only: [ :index, :show ] do
    collection do
      get :panes
    end
  end
  resources :videos, only: [ :index ]
  get "settings", to: "settings#index"
  patch "settings", to: "settings#update"

  get "up" => "rails/health#show", as: :rails_health_check
end
