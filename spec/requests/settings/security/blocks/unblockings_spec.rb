require "rails_helper"

RSpec.describe "Settings::Security::Blocks::Unblockings", type: :request do
  describe "GET /settings/security/blocks/:block_id/unblocking" do
    let(:row) do
      create(:blocked_location,
             fingerprint_hash: ("a" * 64),
             ip_prefix: "1.1.1.0/24")
    end

    it "renders the action-screen for an active block" do
      get settings_security_block_unblocking_path(row)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("unblock block ##{row.id}")
      expect(response.body).to include(row.fingerprint_hash)
      expect(response.body).to include(row.ip_prefix)
      expect(response.body).to include("[unblock]")
      expect(response.body).to include("cancel")
    end

    it "renders the action-screen for an already-unblocked row with no-op copy" do
      unblocked = create(:blocked_location, :unblocked)
      get settings_security_block_unblocking_path(unblocked)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("already unblocked")
    end

    it "404s on an unknown block id" do
      get settings_security_block_unblocking_path(block_id: 999_999)
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      get settings_security_block_unblocking_path(row)
      expect(response).to have_http_status(:found)
    end
  end

  describe "POST /settings/security/blocks/:block_id/unblocking" do
    let(:user)        { User.first || create(:user) }
    let!(:active_row) { create(:blocked_location) }

    it "soft-unblocks the row when confirm=yes" do
      post settings_security_block_unblocking_path(active_row),
           params: { confirm: "yes" }

      expect(response).to redirect_to(settings_security_block_path(active_row))
      expect(flash[:notice]).to match(/unblocked/)

      active_row.reload
      expect(active_row.unblocked_at).to be_present
      expect(active_row.active?).to be(false)
    end

    it "writes an audit-log entry on a successful unblock" do
      expect {
        post settings_security_block_unblocking_path(active_row),
             params: { confirm: "yes" }
      }.to change { AuthAuditLog.where(action: :unblock).count }.by(1)

      log = AuthAuditLog.where(action: :unblock).order(:id).last
      expect(log.target_type).to eq("BlockedLocation")
      expect(log.target_id).to eq(active_row.id)
      expect(log.source_surface).to eq("web")
    end

    it "treats confirm!=yes as cancel" do
      post settings_security_block_unblocking_path(active_row),
           params: { confirm: "no" }

      expect(response).to redirect_to(settings_security_block_path(active_row))
      expect(flash[:alert]).to match(/cancelled/)

      active_row.reload
      expect(active_row.unblocked_at).to be_nil
    end

    it "treats missing confirm param as cancel" do
      post settings_security_block_unblocking_path(active_row)

      expect(response).to redirect_to(settings_security_block_path(active_row))
      expect(flash[:alert]).to match(/cancelled/)
      expect(active_row.reload.unblocked_at).to be_nil
    end

    it "is a no-op on an already-unblocked row (idempotent)" do
      unblocked = create(:blocked_location, :unblocked)
      original_unblocked_at = unblocked.unblocked_at

      expect {
        post settings_security_block_unblocking_path(unblocked),
             params: { confirm: "yes" }
      }.not_to(change { AuthAuditLog.where(action: :unblock).count })

      expect(response).to redirect_to(settings_security_block_path(unblocked))
      expect(flash[:notice]).to match(/already/)
      expect(unblocked.reload.unblocked_at.to_i).to eq(original_unblocked_at.to_i)
    end

    it "404s on an unknown block id" do
      post settings_security_block_unblocking_path(block_id: 999_999),
           params: { confirm: "yes" }
      expect(response).to have_http_status(:not_found)
    end

    it "redirects to /login when unauthenticated", :unauthenticated do
      post settings_security_block_unblocking_path(active_row),
           params: { confirm: "yes" }
      expect(response).to have_http_status(:found)
    end
  end
end
