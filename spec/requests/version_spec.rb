# frozen_string_literal: true

require "rails_helper"

# GET /version — the refresh nudge's reconnect check (G71): the client
# compares this against the page's pito-version meta after a cable reconnect.

RSpec.describe "GET /version", type: :request do
  def login!
    seed = ROTP::Base32.random_base32
    AppSetting.enroll_totp!(seed: seed)
    post "/chat", params: { input: "/login #{ROTP::TOTP.new(seed).now}" }
  end

  it "returns the running build's identity to an authenticated session" do
    login!
    allow(Pito::Version).to receive(:suffix).and_return("1.0.0")

    get "/version", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:ok)
    expect(response.parsed_body).to eq("version" => "1.0.0")
  end

  # No anonymous version disclosure — the standard JSON 401, same as every
  # auth-gated endpoint. The nudge only matters on authenticated pages anyway.
  it "rejects anonymous requests with the standard 401 JSON" do
    get "/version", headers: { "Accept" => "application/json" }

    expect(response).to have_http_status(:unauthorized)
    expect(response.parsed_body["error"]).to eq("unauthenticated")
  end
end
