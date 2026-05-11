require "rails_helper"

# Phase 25 — 01g (LD-11). The login throttle definitions live in
# `config/initializers/rack_attack.rb`. Pin the shape so a future
# refactor cannot silently drop a throttle key, change a limit, or
# break the bracketed-link contract on the throttled response.
RSpec.describe "Rack::Attack login throttles" do
  before { Rack::Attack.cache.store.clear if defined?(Rack::Attack) }

  describe "throttle definitions" do
    it "declares the login/ip throttle with limit 5 per minute" do
      throttle = Rack::Attack.throttles["login/ip"]
      expect(throttle).to be_present
      expect(throttle.limit).to eq(5)
      expect(throttle.period).to eq(60)
    end

    it "declares the login/email throttle with limit 10 per 15 minutes" do
      throttle = Rack::Attack.throttles["login/email"]
      expect(throttle).to be_present
      expect(throttle.limit).to eq(10)
      expect(throttle.period).to eq(15 * 60)
    end

    it "keeps the legacy oauth/token throttle (Phase 12)" do
      throttle = Rack::Attack.throttles["oauth/token"]
      expect(throttle).to be_present
      expect(throttle.limit).to eq(30)
    end
  end

  describe "dev-only allowlist" do
    it "is NOT registered in test (so the throttle specs can drive 127.0.0.1)" do
      expect(Rack::Attack.safelists.keys).not_to include("dev/localhost")
    end
  end

  describe "throttled responder", type: :request do
    it "renders HTML with `login failed.` for login/* throttles (LD-14 — no rate-limit leak)" do
      6.times do
        post "/login", params: { email: "responder@example.test", password: "x" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Content-Type"]).to include("text/html")
      expect(response.body.downcase).to include("login failed.")
      expect(response.body.downcase).not_to include("rate")
      expect(response.body.downcase).not_to include("throttl")
    end

    it "sets Retry-After on the 429" do
      6.times do
        post "/login", params: { email: "retryafter@example.test", password: "x" }
      end

      expect(response.headers["Retry-After"]).to be_present
    end
  end
end
