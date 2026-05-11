require "rails_helper"

# Phase 25 — 01c. Request specs for /login/blocks/:id.
RSpec.describe "Login::Blocks", type: :request do
  let(:pending_user) { create(:user) }
  let(:pending_session) { create(:session, :pending, user: pending_user) }
  let(:fp) { Digest::SHA256.hexdigest("blocks-req-fp") }
  let!(:attempt) do
    create(:login_attempt, :pending,
           user: pending_user,
           fingerprint_hash: fp,
           ip_prefix: "10.20.0.0/24",
           session: pending_session)
  end

  before do
    Auth::GeoEnricher.reset_deferred!
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false)
  end

  describe "GET /login/blocks/:id" do
    it "returns 200 and renders the action-screen with attempt detail" do
      get login_block_path(attempt)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("block new-location login")
      expect(response.body).to include("block the intruder")
      expect(response.body).to include(attempt.fingerprint_short)
    end

    it "marks the submit button as destructive (red)" do
      get login_block_path(attempt)
      expect(response.body).to match(/btn-danger.*block the intruder/m)
    end

    it "redirects when the pending session has expired" do
      pending_session.update_columns(approval_required_until: 1.minute.ago)
      get login_block_path(attempt)
      expect(response).to redirect_to(notifications_path)
    end

    it "redirects when the attempt id is unknown" do
      get login_block_path(id: 999_999_999)
      expect(response).to redirect_to(notifications_path)
    end

    it "requires authentication", :unauthenticated do
      get login_block_path(attempt)
      expect(response).to redirect_to(login_path)
    end
  end

  describe "POST /login/blocks/:id" do
    it "blocks with confirm=yes and revokes the pending session" do
      post login_block_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(notifications_path)
      expect(pending_session.reload.state_revoked?).to be true
    end

    it "creates a BlockedLocation row on block" do
      expect {
        post login_block_path(attempt), params: { confirm: "yes" }
      }.to change(BlockedLocation, :count).by(1)

      row = BlockedLocation.last
      expect(row.fingerprint_hash).to eq(fp)
      expect(row.ip_prefix).to eq("10.20.0.0/24")
      expect(row.source_web?).to be true
    end

    it "writes the audit log row on block" do
      expect {
        post login_block_path(attempt), params: { confirm: "yes" }
      }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.last
      expect(row.action).to eq("block")
      expect(row.source_surface).to eq("web")
      expect(row.target_id).to eq(attempt.id)
    end

    it "stamps the optional reason on the BlockedLocation row" do
      post login_block_path(attempt),
           params: { confirm: "yes", reason: "known bad actor" }
      expect(BlockedLocation.last.reason).to eq("known bad actor")
    end

    it "does NOT block when confirm is missing" do
      post login_block_path(attempt)
      expect(response).to redirect_to(notifications_path)
      expect(pending_session.reload.state_pending_approval?).to be true
      expect(BlockedLocation.count).to eq(0)
    end

    it "redirects with expired flash when the pending window has elapsed" do
      pending_session.update_columns(approval_required_until: 1.minute.ago)
      post login_block_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(notifications_path)
    end

    it "redirects with already-resolved flash when the session was revoked" do
      pending_session.revoke!
      post login_block_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(notifications_path)
    end

    it "requires authentication", :unauthenticated do
      post login_block_path(attempt), params: { confirm: "yes" }
      expect(response).to redirect_to(login_path)
    end
  end
end
