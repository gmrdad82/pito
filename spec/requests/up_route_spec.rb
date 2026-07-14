# frozen_string_literal: true

require "rails_helper"

# 0.7.0 removed the stock health route as dead weight for a single-owner
# tool. P20 (2026-07-14) reinstates it on purpose: the AppSignal uptime
# monitor needs a liveness endpoint to ping, production.rb already silences
# its logs (silence_healthcheck_path), and config/appsignal.rb ignores the
# action so the pings never pollute APM samples.
RSpec.describe "/up health route", type: :request do
  it "responds 200 from the Rails health check (no auth required)" do
    get "/up"
    expect(response).to have_http_status(:ok)
  end

  it "defines the named rails_health_check route" do
    expect(Rails.application.routes.named_routes.names).to include(:rails_health_check)
  end
end
