# frozen_string_literal: true

require "rails_helper"

# 0.7.0 removed the stock `get "up" => "rails/health#show"` health route — this
# is a single-owner local tool, not a load-balanced deployment, so the health
# endpoint is dead weight. The path now falls through to the catch-all 404.
RSpec.describe "Removed /up health route", type: :request do
  it "GET /up no longer resolves to the health check (returns 404 via catch-all)" do
    get "/up"
    expect(response).to have_http_status(:not_found)
  end

  it "no longer defines the named rails_health_check route" do
    expect(Rails.application.routes.named_routes.names).not_to include(:rails_health_check)
  end
end
