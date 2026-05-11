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

  # Drives the controller through the full pipeline: log in (new
  # location) → challenge → approval. After this the integration test
  # cookie jar carries the pre-auth marker with pending_session_id.
  def post_through_pending_branch
    post login_path, params: { email: user.email, password: password }
    post login_challenge_path, params: { challenge_path: "approval" }
  end

  describe "GET /login/pending", :unauthenticated do
    it "renders 200 with attempt detail + countdown when pending is fresh" do
      post_through_pending_branch
      get login_pending_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("waiting for approval")
      expect(response.body).to include("time remaining")
      expect(response.body).to include("[cancel & log out]")
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
