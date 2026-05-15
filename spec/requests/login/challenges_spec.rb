require "rails_helper"

# Phase 25 — 01b. Request specs for /login/challenge.
RSpec.describe "Login::Challenges", type: :request do
  let(:password) { "supersecret" }
  let!(:user) do
    User.first ||
      create(:user, password: password, password_confirmation: password)
  end

  before do
    user.update!(password: password, password_confirmation: password)
  end

  # Phase 29 — Unit A2. After the user-auth refactor, `POST /login` no
  # longer routes a no-TOTP user to `/login/challenge` — a no-TOTP
  # user takes the first-login bootstrap (R4) and a TOTP-configured
  # user is bounced to the `/login/totp` challenge with a pre-auth
  # marker written. `/login/challenge` stays reachable as the TOTP
  # challenge's fallback (`Login::TotpChallengesController#show`
  # redirects there when the marked user is not `totp_enabled?`).
  #
  # To exercise `/login/challenge` and its `approval` branch, this
  # helper establishes a valid pre-auth marker the way the
  # SessionsController does: enable TOTP on the user, `POST /login`
  # (which writes the signed marker + nonce and redirects to
  # `/login/totp`), then clear the TOTP enrollment so the marked user
  # is no longer `totp_enabled?` — putting the challenge flow into the
  # exact state its fallback branch expects.
  def establish_pre_auth_marker_for_challenge!
    user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
    post login_path, params: { username: user.username, password: password }
    user.update!(totp_seed_encrypted: nil, totp_enabled_at: nil, totp_disabled_at: nil)
  end

  describe "GET /login/challenge", :unauthenticated do
    it "redirects to /login without a pre-auth marker" do
      get login_challenge_path
      expect(response).to redirect_to(login_path)
    end

    it "renders 200 with two bracketed-link choices when the marker is set" do
      establish_pre_auth_marker_for_challenge!

      get login_challenge_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[enter 2FA code]")
      expect(response.body).to include("[ask for approval]")
    end
  end

  describe "POST /login/challenge", :unauthenticated do
    before { establish_pre_auth_marker_for_challenge! }

    it "challenge_path=approval creates a pending session and redirects to /login/pending" do
      expect {
        post login_challenge_path, params: { challenge_path: "approval" }
      }.to change(Session.state_pending_approval, :count).by(1)

      expect(response).to redirect_to(login_pending_path)
    end

    it "challenge_path=approval writes a LoginAttempt with reason: new_location_pending" do
      expect {
        post login_challenge_path, params: { challenge_path: "approval" }
      }.to change(LoginAttempt.where(reason: LoginAttempt.reasons[:new_location_pending]), :count).by(1)
    end

    it "challenge_path=totp redirects to the TOTP placeholder" do
      post login_challenge_path, params: { challenge_path: "totp" }
      expect(response).to redirect_to(login_totp_path)
    end

    it "challenge_path=<unknown> renders 422" do
      post login_challenge_path, params: { challenge_path: "garbage" }
      expect(response).to have_http_status(:unprocessable_content)
    end
  end

  describe "POST /login/challenge with no marker", :unauthenticated do
    it "redirects to /login" do
      # The cookie jar is empty — no pre-auth marker. The controller's
      # before_action loads the marker, sees nothing, and bounces.
      post login_challenge_path, params: { challenge_path: "approval" }
      expect(response).to redirect_to(login_path)
    end
  end
end
