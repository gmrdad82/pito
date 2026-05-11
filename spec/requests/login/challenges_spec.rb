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

  def post_login_from_new_location
    # The default test rack request has a stable Accept header / UA, so
    # the fingerprint composer always returns the same hash. No
    # trusted_locations row → the controller treats the pair as new.
    post login_path, params: { email: user.email, password: password }
  end

  describe "GET /login/challenge", :unauthenticated do
    it "redirects to /login without a pre-auth marker" do
      get login_challenge_path
      expect(response).to redirect_to(login_path)
    end

    it "renders 200 with two bracketed-link choices when the marker is set" do
      post_login_from_new_location
      expect(response).to redirect_to(login_challenge_path)

      get login_challenge_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("[enter 2FA code]")
      expect(response.body).to include("[ask for approval]")
    end
  end

  describe "POST /login/challenge", :unauthenticated do
    before { post_login_from_new_location }

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
      # No prior `post_login_from_new_location` — the cookie jar is
      # empty. The controller's before_action loads the marker, sees
      # nothing, and bounces.
      post login_challenge_path, params: { challenge_path: "approval" }
      expect(response).to redirect_to(login_path)
    end
  end

  describe "POST /login → new-location dispatch (Phase 25 — 01b)", :unauthenticated do
    it "does NOT mint a session row" do
      expect {
        post_login_from_new_location
      }.not_to change(Session.state_active, :count)
    end

    it "redirects to /login/challenge" do
      post_login_from_new_location
      expect(response).to redirect_to(login_challenge_path)
    end
  end
end
