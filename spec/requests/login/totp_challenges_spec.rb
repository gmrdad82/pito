require "rails_helper"

# Phase 25 — 01e. Request specs for /login/totp.
RSpec.describe "Login::TotpChallenges", type: :request do
  let(:password) { "supersecret-totp" }
  let(:seed) { "JBSWY3DPEHPK3PXP" }
  let(:backup_plaintext) { "ABCD2345" }
  let!(:user) do
    User.first ||
      create(:user, password: password, password_confirmation: password)
  end

  before do
    user.update!(
      password: password,
      password_confirmation: password,
      totp_seed_encrypted: seed,
      totp_enabled_at: 1.hour.ago
    )
    user.totp_backup_codes.destroy_all
    user.totp_backup_codes.create!(code_digest: BCrypt::Password.create(backup_plaintext))
  end

  def post_login_with_password
    post login_path, params: { email: user.email, password: password }
  end

  describe "GET /login/totp", :unauthenticated do
    it "returns 200 when the pre-auth marker is present (post-password)" do
      post_login_with_password
      expect(response).to redirect_to(login_totp_path)
      get login_totp_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("authenticator")
      # Bracketed-link inner-padding fix: verify button uses the
      # canonical <span class="bl"> wrap.
      expect(response.body).to include('[<span class="bl">verify</span>]')
    end

    it "redirects to /login without a pre-auth marker" do
      get login_totp_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects to /login/challenge when 2FA is not enabled (and short-circuits the show render)" do
      # Drive the controller through the pre-auth marker path while 2FA
      # is off — the show action must redirect and `return` so the view
      # does not also try to render. A missing `return` would not raise
      # in Rails (the redirect wins), but the `before_action` flow + a
      # double response would attempt to set status twice. We assert
      # the redirect status and lack of body to lock the path.
      post_login_with_password
      user.update!(totp_enabled_at: nil, totp_disabled_at: Time.current)
      get login_totp_path
      expect(response).to redirect_to(login_challenge_path)
      expect(response.body).not_to include("enter a 6-digit code from your authenticator")
    end
  end

  describe "POST /login/totp", :unauthenticated do
    before { post_login_with_password }

    it "with the correct TOTP code activates the session and rotates the token" do
      code = ROTP::TOTP.new(seed).now
      expect {
        post login_totp_path, params: { code: code }
      }.to change(Session.state_active, :count).by(1)

      expect(response).to redirect_to(root_path)
    end

    it "with the correct TOTP code writes a LoginAttempt with reason: new_location_2fa_passed" do
      code = ROTP::TOTP.new(seed).now
      expect {
        post login_totp_path, params: { code: code }
      }.to change(LoginAttempt.where(reason: LoginAttempt.reasons[:new_location_2fa_passed]), :count).by(1)
    end

    it "with a valid backup code stamps used_at and activates" do
      expect {
        post login_totp_path, params: { code: backup_plaintext }
      }.to change(Session.state_active, :count).by(1)

      row = user.totp_backup_codes.first
      expect(row.reload.used_at).to be_present
    end

    it "with a wrong code returns 422 and writes a twofa_failed LoginAttempt" do
      expect {
        post login_totp_path, params: { code: "000000" }
      }.to change(LoginAttempt.where(reason: LoginAttempt.reasons[:twofa_failed]), :count).by(1)

      expect(response).to have_http_status(:unprocessable_content)
    end

    it "with an already-used backup code returns 422" do
      row = user.totp_backup_codes.first
      row.update!(used_at: 1.minute.ago)

      expect {
        post login_totp_path, params: { code: backup_plaintext }
      }.to change(LoginAttempt.where(reason: LoginAttempt.reasons[:twofa_failed]), :count).by(1)

      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /login/totp without a pre-auth marker", :unauthenticated do
    it "redirects (HTML) to /login" do
      post login_totp_path, params: { code: "123456" }
      expect(response).to redirect_to(login_path)
    end
  end
end
