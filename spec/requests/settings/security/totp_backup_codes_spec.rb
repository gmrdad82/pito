require "rails_helper"

# Phase 25 — 01e. Request specs for /settings/security/totp_backup_codes.
RSpec.describe "Settings::Security::TotpBackupCodes", type: :request do
  let(:seed) { "JBSWY3DPEHPK3PXP" }
  let(:password) { "password123" }
  let(:user) { User.first || create(:user) }

  before do
    user.update!(
      password: password,
      password_confirmation: password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago
    )
    # P25 follow-up — F9. Reset the replay-defense watermark so each
    # test computes a fresh-window verify and is not blocked by a
    # prior test's stamp within the same 30-s window.
    user.update_columns(totp_last_used_step: nil)
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
      # Bracketed-link inner-padding fix: label wrapped in <span class="bl">.
      expect(response.body).to include('[<span class="bl">regenerate</span>]')
    end

    it "asks for both password and TOTP code on the regenerate screen" do
      get settings_security_new_totp_backup_codes_path
      expect(response.body).to include('name="password"')
      expect(response.body).to include('name="code"')
      expect(response.body).to include("password")
      expect(response.body).to include("authenticator app")
    end

    # 2026-05-11 form-pane sweep — the regenerate form sits inside
    # `.pane.pane--standalone` like every other standalone new page.
    it "wraps the regenerate form in a .pane.pane--standalone" do
      get settings_security_new_totp_backup_codes_path
      html = Nokogiri::HTML.fragment(response.body)
      pane = html.at_css("div.pane.pane--standalone")
      expect(pane).not_to be_nil
      expect(pane.at_css('input[name="password"]')).not_to be_nil
      expect(pane.at_css('input[name="code"]')).not_to be_nil
    end
  end

  describe "POST /settings/security/totp_backup_codes" do
    it "regenerates 10 new codes when confirm=yes + correct password + correct code" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_backup_codes_path,
           params: { confirm: "yes", password: password, code: code }
      expect(response).to redirect_to(settings_security_totp_backup_codes_path)
      follow_redirect!
      expect(response.body).to include("new codes")
      expect(user.reload.totp_backup_codes.count).to eq(10)
    end

    it "returns 422 when the code is wrong (password right)" do
      post settings_security_totp_backup_codes_path,
           params: { confirm: "yes", password: password, code: "000000" }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash.now[:alert]).to include("credentials don't match")
    end

    it "returns 422 when the password is wrong (code right) and copy is generic" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_backup_codes_path,
           params: { confirm: "yes", password: "nope", code: code }
      expect(response).to have_http_status(:unprocessable_content)
      expect(flash.now[:alert]).to include("credentials don't match")
      # Generic copy — must not leak which field failed.
      expect(flash.now[:alert]).not_to match(/password/i)
      expect(flash.now[:alert]).not_to match(/code|totp/i)
    end

    it "returns 422 when the password is blank" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_backup_codes_path,
           params: { confirm: "yes", password: "", code: code }
      expect(response).to have_http_status(:unprocessable_content)
    end

    it "redirects on confirm != yes" do
      code = ROTP::TOTP.new(seed).now
      post settings_security_totp_backup_codes_path,
           params: { confirm: "no", password: password, code: code }
      expect(response).to redirect_to(settings_security_totp_backup_codes_path)
    end
  end
end
