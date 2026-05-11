require "rails_helper"

# Phase 25 — 01g (LD-11). Login throttles. Two buckets:
#
#   * `login/ip`     — 5 POSTs / minute from one IP across all login
#                      endpoints.
#   * `login/email`  — 10 POSTs / 15 minutes keyed on the lowercased
#                      email param (SHA256-hashed in the cache key).
#
# Both render the generic `login failed.` copy on the 429 — the user
# must NOT see the rate-limit reason (LD-14). The throttled row
# lands in `LoginAttempt` with `reason: rate_limited`.
RSpec.describe "Sessions rate limit", type: :request do
  let(:password) { "supersecret123" }
  let!(:user) do
    User.first ||
      create(:user, email: "throttle-target@example.test",
             password: password, password_confirmation: password)
  end

  before do
    user.update!(email: "throttle-target@example.test",
                 password: password, password_confirmation: password)
    Rack::Attack.cache.store.clear
  end

  describe "per-IP throttle (5 / minute)" do
    it "returns 429 on the 6th POST within 1 minute from one IP" do
      5.times do
        post login_path, params: { email: "missing-#{SecureRandom.hex(3)}@example.test", password: "x" }
        # Each non-throttled attempt may render the form (422) or
        # similar; we only care that the 6th flips to 429.
        expect(response).not_to have_http_status(:too_many_requests)
      end

      post login_path, params: { email: "missing-#{SecureRandom.hex(3)}@example.test", password: "x" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "renders the generic `login failed.` copy on the 429 (LD-14 — no rate-limit leak)" do
      6.times do
        post login_path, params: { email: "missing@example.test", password: "x" }
      end
      expect(response.body.downcase).to include("login failed.")
      expect(response.body.downcase).not_to include("rate")
      expect(response.body.downcase).not_to include("throttl")
    end

    it "writes a LoginAttempt row with reason: rate_limited on the 429" do
      # Burn the first five attempts to set up the throttle.
      5.times do
        post login_path, params: { email: "throttle-target@example.test", password: "x" }
      end

      # The throttle trips on the 6th request. The throttled_responder
      # calls Auth::RateLimitLogger.call which writes the row.
      expect {
        post login_path, params: { email: "throttle-target@example.test", password: "x" }
      }.to change { LoginAttempt.where(reason: LoginAttempt.reasons[:rate_limited]).count }.by_at_least(1)
    end
  end

  describe "per-email throttle (10 / 15 minutes)" do
    # Bypass the per-IP throttle by rotating the IP between attempts.
    # `request.remote_ip` reads `X-Forwarded-For` first; in a Rails
    # integration spec we set it via the `headers:` hash.
    def rotating_ip_post(index, email:)
      post login_path,
           params: { email: email, password: "x" },
           headers: { "REMOTE_ADDR" => "10.0.#{index}.1" }
    end

    it "returns 429 on the 11th POST for the same email across rotating IPs" do
      10.times do |i|
        rotating_ip_post(i, email: "rotate@example.test")
        expect(response).not_to have_http_status(:too_many_requests)
      end

      rotating_ip_post(99, email: "rotate@example.test")
      expect(response).to have_http_status(:too_many_requests)
    end

    it "is case-insensitive on the email key" do
      9.times do |i|
        rotating_ip_post(i, email: "Mixed@Example.Test")
      end
      rotating_ip_post(50, email: "mixed@example.test")
      expect(response).not_to have_http_status(:too_many_requests)

      # 11th total under either casing flips the per-email bucket.
      rotating_ip_post(51, email: "MIXED@example.TEST")
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "the per-IP bucket trips even when emails alternate" do
    it "still 429s the 6th /login POST regardless of email differences" do
      6.times do |i|
        post login_path, params: { email: "alt-#{i}@example.test", password: "x" }
      end
      expect(response).to have_http_status(:too_many_requests)
    end
  end

  describe "the throttled response shape" do
    it "carries a Retry-After header" do
      6.times do
        post login_path, params: { email: "rh@example.test", password: "x" }
      end
      expect(response.headers["Retry-After"]).to be_present
    end

    it "is HTML, not JSON (the user sees a friendly screen)" do
      6.times do
        post login_path, params: { email: "html@example.test", password: "x" }
      end
      expect(response.headers["Content-Type"]).to include("text/html")
    end
  end
end
