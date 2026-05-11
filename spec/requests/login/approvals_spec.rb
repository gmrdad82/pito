require "rails_helper"

# Phase 25 — 01c. Request specs for /login/approvals/:id.
RSpec.describe "Login::Approvals", type: :request do
  let(:pending_user) { create(:user) }
  let(:operator) do
    # The signed-in operator on a trusted device. The default
    # `spec/support/auth.rb` before-hook signs in `User.first` —
    # which is the pending_user above unless we create the operator
    # first.
    pending_user
    create(:user)
  end
  let(:pending_session) { create(:session, :pending, user: pending_user) }
  let(:fp) { Digest::SHA256.hexdigest("approvals-req-fp") }
  let!(:attempt) do
    create(:login_attempt, :pending,
           user: pending_user,
           fingerprint_hash: fp,
           ip_prefix: "10.10.0.0/24",
           session: pending_session)
  end

  before do
    Auth::GeoEnricher.reset_deferred!
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false)
  end

  describe "GET /login/approvals/:id" do
    it "returns 200 and renders the action-screen with attempt detail" do
      get login_approval_path(attempt)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("approve new-location login")
      expect(response.body).to include("yeah, it&#39;s me").or include("yeah, it's me")
      expect(response.body).to include(attempt.fingerprint_short)
    end

    it "renders the bracketed cancel link" do
      get login_approval_path(attempt)
      expect(response.body).to include('<span class="bl">cancel</span>')
    end

    it "redirects when the pending session has expired" do
      pending_session.update_columns(approval_required_until: 1.minute.ago)
      get login_approval_path(attempt)
      expect(response).to redirect_to(notifications_path)
      follow_redirect!
      expect(response.body).to include("expired")
    end

    it "redirects when the pending session is already revoked" do
      pending_session.revoke!
      get login_approval_path(attempt)
      expect(response).to redirect_to(notifications_path)
    end

    it "redirects when the attempt id is unknown" do
      get login_approval_path(id: 999_999_999)
      expect(response).to redirect_to(notifications_path)
    end

    it "redirects when the attempt has no session_id" do
      orphan = create(:login_attempt, :pending,
                      user: pending_user, session: nil,
                      fingerprint_hash: fp,
                      ip_prefix: "10.10.0.0/24")
      get login_approval_path(orphan)
      expect(response).to redirect_to(notifications_path)
    end

    it "redirects unauthenticated callers to /login", :unauthenticated do
      get login_approval_path(attempt)
      expect(response).to redirect_to(login_path)
    end
  end

  describe "POST /login/approvals/:id" do
    it "approves with confirm=yes and redirects to /notifications" do
      post login_approval_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(notifications_path)
      expect(pending_session.reload.state_active?).to be true
    end

    it "writes the audit log row on approve" do
      expect {
        post login_approval_path(attempt), params: { confirm: "yes" }
      }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.last
      expect(row.action).to eq("approve")
      expect(row.source_surface).to eq("web")
      expect(row.target_id).to eq(attempt.id)
    end

    it "does NOT activate the session when confirm is missing" do
      post login_approval_path(attempt)
      expect(response).to redirect_to(notifications_path)
      expect(pending_session.reload.state_pending_approval?).to be true
    end

    it "does NOT activate the session when confirm is 'no'" do
      post login_approval_path(attempt), params: { confirm: "no" }
      expect(pending_session.reload.state_pending_approval?).to be true
    end

    it "redirects with expired flash when the pending window has elapsed" do
      pending_session.update_columns(approval_required_until: 1.minute.ago)
      post login_approval_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(notifications_path)
      follow_redirect!
      expect(response.body).to include("expired")
    end

    it "redirects with already-resolved flash when the session was revoked" do
      pending_session.revoke!
      post login_approval_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(notifications_path)
    end

    it "requires authentication", :unauthenticated do
      post login_approval_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(login_path)
    end
  end
end
