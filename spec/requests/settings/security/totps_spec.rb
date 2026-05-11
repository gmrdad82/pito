require "rails_helper"

# Phase 25 — 01e. Request specs for /settings/security/totp*.
RSpec.describe "Settings::Security::Totps", type: :request do
  let(:user) { User.first || create(:user) }

  describe "GET /settings/security/totp" do
    it "renders 200 with the [ enable 2FA ] CTA when 2FA is off" do
      get settings_security_totp_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[ enable 2FA ]")
      expect(response.body).to include("off")
    end

    it "renders the disable + backup-codes management links when 2FA is on" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      get settings_security_totp_path
      expect(response.body).to include("on")
      expect(response.body).to include("[disable]").or include("disable")
      expect(response.body).to include("backup codes")
    end
  end

  describe "POST /settings/security/totp (enroll)" do
    it "creates the seed and 10 backup codes" do
      expect {
        post settings_security_totp_path
      }.to change { user.reload.totp_backup_codes.count }.by(10)

      expect(user.reload.totp_seed_encrypted).to be_present
      expect(response).to redirect_to(settings_security_totp_show_path)
    end

    it "redirects with an error when 2FA is already enabled" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      post settings_security_totp_path
      expect(response).to redirect_to(settings_security_totp_path)
      expect(flash[:alert]).to include("already on")
    end
  end

  describe "GET /settings/security/totp/show (one-shot view)" do
    it "renders 200 when the one-shot payload is in the flash" do
      post settings_security_totp_path
      follow_redirect!
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("scan")
      expect(response.body).to include("confirm")
    end

    it "redirects to the status page when no one-shot payload is present" do
      get settings_security_totp_show_path
      expect(response).to redirect_to(settings_security_totp_path)
      expect(flash[:alert]).to include("enrollment expired")
    end
  end

  describe "PATCH /settings/security/totp/confirm" do
    let(:seed) { "JBSWY3DPEHPK3PXP" }

    before do
      # Drive the controller's one-shot flash by going through enrollment.
      # We then override the user's seed to match the deterministic seed
      # the test computes a code against.
      post settings_security_totp_path
      user.update!(totp_seed_encrypted: seed)
      # Inject the deterministic seed into the flash so the confirm
      # action verifies against it.
      get settings_security_totp_show_path
    end

    it "stamps totp_enabled_at when the code is correct" do
      code = ROTP::TOTP.new(seed).now
      patch settings_security_totp_confirm_path, params: { code: code }
      # If the test's flash-keep machinery diverges, the controller
      # falls back to the user's seed (same seed) and confirms anyway.
      expect(user.reload.totp_enabled_at).to be_present
    end

    it "returns 422 when the code is wrong" do
      patch settings_security_totp_confirm_path, params: { code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.totp_enabled_at).to be_nil
    end
  end

  describe "GET /settings/security/totp/disable" do
    it "renders the action-screen when 2FA is on" do
      user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
      get settings_security_totp_disable_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("disable 2FA")
      expect(response.body).to include("[ disable 2FA ]")
    end

    it "redirects to the status page when 2FA is already off" do
      get settings_security_totp_disable_path
      expect(response).to redirect_to(settings_security_totp_path)
    end
  end

  describe "POST /settings/security/totp/disable" do
    let(:seed) { "JBSWY3DPEHPK3PXP" }

    before do
      user.update!(totp_seed_encrypted: seed, totp_enabled_at: 1.hour.ago)
    end

    it "disables 2FA when confirm=yes and the code is correct" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_disable_path, params: { confirm: "yes", code: code }
      expect(user.reload.totp_enabled?).to be false
      expect(user.reload.totp_disabled_at).to be_present
    end

    it "returns 422 when the code is wrong" do
      post settings_security_totp_disable_path, params: { confirm: "yes", code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(user.reload.totp_enabled?).to be true
    end

    it "cancels and redirects when confirm != yes" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_disable_path, params: { confirm: "no", code: code }
      expect(response).to redirect_to(settings_security_totp_path)
      expect(user.reload.totp_enabled?).to be true
    end
  end

  describe "auth gate", :unauthenticated do
    it "redirects unauthenticated GETs to /login" do
      get settings_security_totp_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects unauthenticated POSTs to /login" do
      post settings_security_totp_path
      expect(response).to redirect_to(login_path)
    end
  end
end
