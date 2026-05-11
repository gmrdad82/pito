require "rails_helper"

# Phase 25 — 01e. Request specs for /settings/security/totp_backup_codes.
RSpec.describe "Settings::Security::TotpBackupCodes", type: :request do
  let(:seed) { "JBSWY3DPEHPK3PXP" }
  let(:user) { User.first || create(:user) }

  before do
    user.update!(totp_seed_encrypted: seed, totp_enabled_at: 1.hour.ago)
  end

  describe "GET /settings/security/totp_backup_codes" do
    it "renders 200 with the unused count" do
      3.times { user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("ABCD234#{rand(9)}")) }
      get settings_security_totp_backup_codes_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("unused")
    end

    it "does not display any plaintext codes" do
      user.totp_backup_codes.create!(code_digest: BCrypt::Password.create("VISIBLE2"))
      get settings_security_totp_backup_codes_path
      expect(response.body).not_to include("VISIBLE2")
    end

    it "redirects when 2FA is off" do
      user.update!(totp_seed_encrypted: nil, totp_enabled_at: nil, totp_disabled_at: Time.current)
      get settings_security_totp_backup_codes_path
      expect(response).to redirect_to(settings_security_totp_path)
    end
  end

  describe "GET /settings/security/totp_backup_codes/new" do
    it "renders the action-screen confirmation" do
      get settings_security_new_totp_backup_codes_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("regenerate")
      expect(response.body).to include("[ regenerate ]")
    end
  end

  describe "POST /settings/security/totp_backup_codes" do
    it "regenerates 10 new codes when confirm=yes + correct code" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_backup_codes_path, params: { confirm: "yes", code: code }
      expect(response).to redirect_to(settings_security_totp_backup_codes_path)
      follow_redirect!
      expect(response.body).to include("new codes")
      expect(user.reload.totp_backup_codes.count).to eq(10)
    end

    it "returns 422 when the code is wrong" do
      post settings_security_totp_backup_codes_path, params: { confirm: "yes", code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects on confirm != yes" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_backup_codes_path, params: { confirm: "no", code: code }
      expect(response).to redirect_to(settings_security_totp_backup_codes_path)
    end
  end
end
