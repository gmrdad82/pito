require "rails_helper"

# P25 follow-up — F1. Rate-limit defense-in-depth on the destructive
# `/settings/security/totp*` endpoints. The endpoints are already
# password+TOTP gated, but a stolen session cookie could otherwise
# brute-force the password+TOTP combo at full rate. Bucket: 10 POSTs
# per 15 minutes per IP, matching `login/email`.
RSpec.describe "Rack::Attack settings/totp throttle (P25 F1)" do
  before { Rack::Attack.cache.store.clear if defined?(Rack::Attack) }

  describe "throttle definition" do
    it "declares the settings/totp throttle with limit 10 per 15 minutes" do
      throttle = Rack::Attack.throttles["settings/totp"]
      expect(throttle).to be_present
      expect(throttle.limit).to eq(10)
      expect(throttle.period).to eq(15 * 60)
    end
  end

  describe "throttle behavior", type: :request do
    let(:password) { "supersecret-pw" }
    let(:seed) { "JBSWY3DPEHPK3PXP" }
    let(:user) do
      u = User.first || create(:user)
      u.update!(
        password: password,
        password_confirmation: password,
        totp_seed_encrypted: seed,
        totp_enabled_at: 1.hour.ago
      )
      u
    end

    before { user }

    it "lets the first 10 POSTs through (each handled by the controller, regardless of 200/422)" do
      10.times do
        post settings_security_totp_disable_path,
             params: { confirm: "yes", password: "wrong", code: "000000" }
        expect(response).not_to have_http_status(:too_many_requests)
      end
    end

    it "trips a 429 on the 11th POST in the window" do
      10.times do
        post settings_security_totp_disable_path,
             params: { confirm: "yes", password: "wrong", code: "000000" }
      end
      post settings_security_totp_disable_path,
           params: { confirm: "yes", password: "wrong", code: "000000" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "trips a 429 across mixed POST paths under /settings/security/totp* (regenerate + disable)" do
      # 5 to disable, 5 to backup-codes regenerate → 10 in the bucket.
      5.times do
        post settings_security_totp_disable_path,
             params: { confirm: "yes", password: "wrong", code: "000000" }
      end
      5.times do
        post settings_security_totp_backup_codes_path,
             params: { confirm: "yes", password: "wrong", code: "000000" }
      end
      # 11th request — any TOTP destructive verb.
      post settings_security_totp_disable_path,
           params: { confirm: "yes", password: "wrong", code: "000000" }
      expect(response).to have_http_status(:too_many_requests)
    end

    it "renders a generic 'too many attempts.' HTML body (no rate-limit leak)" do
      11.times do
        post settings_security_totp_disable_path,
             params: { confirm: "yes", password: "wrong", code: "000000" }
      end
      expect(response).to have_http_status(:too_many_requests)
      expect(response.headers["Content-Type"]).to include("text/html")
      expect(response.body.downcase).to include("too many attempts")
      expect(response.body.downcase).not_to include("rate-limit")
      expect(response.body.downcase).not_to include("throttl")
    end

    it "sets Retry-After on the 429" do
      11.times do
        post settings_security_totp_disable_path,
             params: { confirm: "yes", password: "wrong", code: "000000" }
      end
      expect(response.headers["Retry-After"]).to eq((15 * 60).to_s)
    end

    it "does NOT throttle GET requests to /settings/security/totp" do
      # GETs are safe — only destructive verbs burn the bucket.
      20.times { get settings_security_totp_path }
      expect(response).to have_http_status(:ok).or have_http_status(:found)
    end

    it "does NOT throttle requests to unrelated paths under /settings" do
      20.times { get settings_security_path }
      expect(response).not_to have_http_status(:too_many_requests)
    end
  end
end
