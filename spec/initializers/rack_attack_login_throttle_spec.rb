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
        post "/login", params: { username: "responder_user", password: "x" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Content-Type"]).to include("text/html")
      expect(response.body.downcase).to include("login failed.")
      expect(response.body.downcase).not_to include("rate")
      expect(response.body.downcase).not_to include("throttl")
    end

    it "sets Retry-After on the 429" do
      6.times do
        post "/login", params: { username: "retryafter_user", password: "x" }
      end

      expect(response.headers["Retry-After"]).to be_present
    end
  end

  # Phase 29 — Unit A2 follow-up — security finding F4.
  #
  # The `password/*` throttled responder did NOT write a `LoginAttempt`
  # row when a request was throttled (forensic gap). The `login/*`
  # responder always writes one via `Auth::RateLimitLogger`. The fix
  # mirrors the `login/*` pattern so an attacker who trips the
  # password-recovery throttle leaves a trace on the operator's
  # `/settings/security/attempts` page.
  describe "password/* throttled responder writes a LoginAttempt row (F4)", type: :request do
    it "writes a LoginAttempt row when password/ip trips" do
      expect {
        6.times do |i|
          post "/password/reset",
               params: { username: "f4_ip_target", code: "000000" },
               headers: { "REMOTE_ADDR" => "10.99.0.1" }
        end
      }.to change(LoginAttempt, :count).by_at_least(1)

      expect(response).to have_http_status(:too_many_requests)
      expect(response.body.downcase).to include("reset failed.")

      # The throttle row is reachable from the attempt-log table — the
      # whole point of F4. `reason: :rate_limited` matches the `login/`
      # branch (shared logger). The IP is recorded so an operator can
      # correlate the burst.
      throttled = LoginAttempt.where(reason: :rate_limited, ip: "10.99.0.1").order(:created_at).last
      expect(throttled).to be_present
      expect(throttled.result_failed?).to be(true)
      expect(throttled.email_attempted).to eq("f4_ip_target")
    end

    it "writes a LoginAttempt row when password/username trips across rotating IPs" do
      starting = LoginAttempt.count

      11.times do |i|
        post "/password/reset",
             params: { username: "f4_user_target", code: "000000" },
             headers: { "REMOTE_ADDR" => "10.50.#{i}.1" }
      end

      expect(response).to have_http_status(:too_many_requests)
      expect(LoginAttempt.count).to be > starting

      # The username-bucket throttle row is reachable too.
      rows = LoginAttempt.where(reason: :rate_limited).where("email_attempted = ?", "f4_user_target")
      expect(rows).not_to be_empty
    end

    it "the response body does not leak the rate-limit reason on a password/* trip" do
      6.times do
        post "/password/reset",
             params: { username: "f4_no_leak_target", code: "000000" },
             headers: { "REMOTE_ADDR" => "10.99.7.1" }
      end

      expect(response.body.downcase).not_to include("rate")
      expect(response.body.downcase).not_to include("throttl")
    end
  end
end
