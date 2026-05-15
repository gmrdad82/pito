require "rails_helper"

# Phase 25 — 01g (LD-11). RateLimitLogger writes a LoginAttempt row
# every time Rack::Attack (or the in-controller throttle) trips on a
# login surface.
RSpec.describe Auth::RateLimitLogger do
  let(:user) { create(:user, username: "ratelimited_user") }
  let(:request) do
    ActionDispatch::TestRequest.create.tap do |r|
      r.env["REMOTE_ADDR"] = "1.2.3.4"
      r.env["HTTP_USER_AGENT"] = "RateLimiter/1.0"
    end
  end

  describe ".call (happy)" do
    it "writes a row with result: failed, reason: rate_limited" do
      expect {
        described_class.call(request: request)
      }.to change(LoginAttempt, :count).by(1)

      row = LoginAttempt.recent.first
      expect(row.result).to eq("failed")
      expect(row.reason).to eq("rate_limited")
      expect(row.ip.to_s).to eq("1.2.3.4")
    end

    it "associates the row with a known user when username maps to one" do
      user # touch to create
      described_class.call(request: request, username: "ratelimited_user")

      row = LoginAttempt.recent.first
      expect(row.user_id).to eq(user.id)
      expect(row.email_attempted).to eq("ratelimited_user")
    end

    it "leaves user_id nil when the username does not map" do
      described_class.call(request: request, username: "unknown_user")

      row = LoginAttempt.recent.first
      expect(row.user_id).to be_nil
      expect(row.email_attempted).to eq("unknown_user")
    end

    it "captures the IP and a /24 ip_prefix" do
      described_class.call(request: request)
      row = LoginAttempt.recent.first

      expect(row.ip.to_s).to eq("1.2.3.4")
      expect(row.ip_prefix).to eq("1.2.3.0/24")
    end

    it "composes a 64-char fingerprint hash" do
      described_class.call(request: request)
      row = LoginAttempt.recent.first

      expect(row.fingerprint_hash.length).to eq(64)
    end
  end

  describe ".call (sad)" do
    it "works without a request — synthesizes a placeholder fingerprint" do
      described_class.call(
        request: nil,
        ip: "5.6.7.8",
        user_agent: "fallback-ua",
        username: "ghost_user"
      )

      row = LoginAttempt.recent.first
      expect(row.result).to eq("failed")
      expect(row.reason).to eq("rate_limited")
      expect(row.ip.to_s).to eq("5.6.7.8")
      expect(row.fingerprint_hash.length).to eq(64)
    end

    it "falls back to 0.0.0.0 when neither request nor ip is supplied" do
      described_class.call(request: nil)
      row = LoginAttempt.recent.first

      expect(row.ip.to_s).to eq("0.0.0.0")
      expect(row.user_agent).to eq("(rate-limited)")
    end

    it "returns nil and logs a warning when LoginAttempt.create! raises" do
      allow(LoginAttempt).to receive(:create!).and_raise(ActiveRecord::RecordInvalid.new(LoginAttempt.new))
      expect(Rails.logger).to receive(:warn).with(/RateLimitLogger/)

      result = described_class.call(request: request)
      expect(result).to be_nil
    end
  end
end
