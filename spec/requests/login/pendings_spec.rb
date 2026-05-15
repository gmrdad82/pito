require "rails_helper"

# Phase 25 — 01b. Request specs for /login/pending.
RSpec.describe "Login::Pendings", type: :request do
  let(:password) { "supersecret" }
  let!(:user) do
    User.first ||
      create(:user, password: password, password_confirmation: password)
  end

  before do
    user.update!(password: password, password_confirmation: password)
  end

  # Phase 29 — Unit A2. `POST /login` no longer routes a no-TOTP user
  # to `/login/challenge` (the first-login bootstrap, R4, takes over).
  # The `/login/challenge` → `approval` branch is still reachable via
  # the pre-auth marker, which `SessionsController#create` writes for
  # a TOTP-configured user. Establish that marker the way the
  # controller does (enable TOTP, `POST /login`, then clear the
  # enrollment so the marked user is no longer `totp_enabled?`), then
  # drive the approval branch.
  def post_through_pending_branch
    user.update!(totp_seed_encrypted: "JBSWY3DPEHPK3PXP", totp_enabled_at: 1.hour.ago)
    post login_path, params: { username: user.username, password: password }
    user.update!(totp_seed_encrypted: nil, totp_enabled_at: nil, totp_disabled_at: nil)
    post login_challenge_path, params: { challenge_path: "approval" }
  end

  describe "GET /login/pending", :unauthenticated do
    it "renders 200 with attempt detail + countdown when pending is fresh" do
      post_through_pending_branch
      get login_pending_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("waiting for approval")
      expect(response.body).to include("time remaining")
      # HTML-escaped ampersand keeps the page valid; the visible label
      # is `[cancel & log out]` (the entity decodes in the browser).
      expect(response.body).to include("[cancel &amp; log out]")
    end

    it "redirects to /login when no pre-auth marker is set" do
      get login_pending_path
      expect(response).to redirect_to(login_path)
    end

    it "redirects to /login when the pending row has been transitioned to :expired" do
      post_through_pending_branch
      Session.state_pending_approval.find_each { |s| s.update_columns(state: Session.states[:expired]) }
      get login_pending_path
      expect(response).to redirect_to(login_path)
    end

    it "renders the deadline as ISO 8601 in the data attribute" do
      post_through_pending_branch
      get login_pending_path
      expect(response.body).to match(/data-pending-countdown-deadline-value="[^"]+"/)
    end
  end

  describe "DELETE /login/pending — [cancel & log out]", :unauthenticated do
    it "revokes the pending session and clears the marker" do
      post_through_pending_branch
      session = Session.state_pending_approval.last
      expect(session).to be_present

      delete login_pending_path
      expect(response).to redirect_to(login_path)
      expect(session.reload.state).to eq("revoked")
    end

    it "is a no-op redirect when no marker is set" do
      delete login_pending_path
      expect(response).to redirect_to(login_path)
    end
  end
end
