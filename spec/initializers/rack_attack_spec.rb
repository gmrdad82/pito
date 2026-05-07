require "rails_helper"

# Phase 3 — Step B (5b-token-and-auth-concern.md). The throttle uses
# `Rack::Attack.cache.store` which the initializer pins to a MemoryStore
# in test. Each example clears the store first to avoid cross-pollution
# between examples and across the rack_app_auth spec.
RSpec.describe "Rack::Attack failed-auth throttle", type: :request do
  before do
    Rack::Attack.cache.store.clear
  end

  it "returns 429 after #{ApiAuthThrottle::LIMIT} failed lookups from one IP" do
    headers = {
      "Content-Type" => "application/json",
      "Accept" => "application/json",
      "Authorization" => "Bearer absolutely-bogus"
    }

    payload = {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: {
        protocolVersion: "2025-03-26", capabilities: {},
        clientInfo: { name: "test", version: "1.0" }
      }
    }.to_json

    # First N failures return 401. The (N+1)th gets the 429 from
    # `Rack::Attack.blocklist`.
    ApiAuthThrottle::LIMIT.times do
      post "/mcp", params: payload, headers: headers
      expect(response).to have_http_status(:unauthorized)
    end

    post "/mcp", params: payload, headers: headers
    expect(response).to have_http_status(:too_many_requests)

    body = JSON.parse(response.body)
    expect(body["error"]).to eq("rate_limited")
    expect(body["retry_after"]).to be_a(Integer)
  end

  it "does not throttle the cookie-based HTML routes" do
    Current.tenant = Tenant.first || create(:tenant)
    # The HTML root path doesn't match `/mcp` or `/api/`. Even if a
    # request from a "blocked" IP had an Authorization header (it doesn't,
    # cookies-only), the path check excludes it. Hammer the bucket key
    # manually and assert the HTML route still 200s.
    (ApiAuthThrottle::LIMIT * 2).times { ApiAuthThrottle.record_failure("127.0.0.1") }

    get "/"
    # The dashboard root may render or 500 on missing data, but it
    # should NOT be a 429.
    expect(response).not_to have_http_status(:too_many_requests)
  ensure
    Current.reset
  end

  it "successful auth does NOT increment the bucket" do
    tenant = Tenant.first || create(:tenant)
    user   = User.first   || create(:user, tenant: tenant)
    _r, plaintext = ApiToken.generate!(
      tenant: tenant, user: user, name: "ok",
      scopes: Scopes::ALL.dup
    )

    payload = {
      jsonrpc: "2.0", id: 1, method: "initialize",
      params: {
        protocolVersion: "2025-03-26", capabilities: {},
        clientInfo: { name: "test", version: "1.0" }
      }
    }.to_json

    20.times do
      post "/mcp", params: payload,
           headers: {
             "Content-Type" => "application/json",
             "Accept" => "application/json",
             "Authorization" => "Bearer #{plaintext}"
           }
      expect(response).to have_http_status(:ok)
    end
  end
end
