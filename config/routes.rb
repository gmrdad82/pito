require "sidekiq/web"
require "sidekiq/cron/web"

Rails.application.routes.draw do
  # TODO: protect when multi-tenant
  mount Sidekiq::Web => "/sidekiq"

  get "up" => "rails/health#show", as: :rails_health_check

  # root "dashboard#index"
end
