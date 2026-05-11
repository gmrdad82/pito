require "rails_helper"

# Phase 25 — 01g (LD-13). Bulk-purge actions audit-log a row to
# AuthAuditLog so the long-term audit trail captures the operator,
# the surface, the filter, and the deletion count.
RSpec.describe "Settings::Security purge audit logging", type: :request do
  let(:user) { User.first || create(:user) }

  describe "POST /settings/security/blocks/purge with confirm=yes" do
    let!(:row) { create(:blocked_location, fingerprint_hash: "aa" * 32) }

    it "writes an AuthAuditLog row with action: :purge" do
      expect {
        post settings_security_blocks_purge_path,
             params: { fingerprint: row.fingerprint_hash, confirm: "yes" }
      }.to change { AuthAuditLog.where(action: :purge).count }.by(1)
    end

    it "captures the filter and deleted_count in metadata" do
      post settings_security_blocks_purge_path,
           params: { fingerprint: row.fingerprint_hash, confirm: "yes" }

      log = AuthAuditLog.where(action: :purge).order(:created_at).last
      expect(log.source_surface).to eq("web")
      expect(log.target_type).to eq("BlockedLocation")
      expect(log.metadata["kind"]).to eq("blocks")
      expect(log.metadata["deleted_count"]).to be >= 1
      expect(log.metadata["filter"]).to be_a(Hash)
    end

    it "does NOT audit-log when confirm is missing" do
      expect {
        post settings_security_blocks_purge_path,
             params: { fingerprint: row.fingerprint_hash }
      }.not_to change { AuthAuditLog.where(action: :purge).count }
    end
  end

  describe "POST /settings/security/attempts/purge with confirm=yes" do
    let!(:la) { create(:login_attempt, user: user, ip: "9.9.9.9") }

    it "writes an AuthAuditLog row with action: :purge" do
      expect {
        post settings_security_attempts_purge_path,
             params: { ip: "9.9.9.9", confirm: "yes" }
      }.to change { AuthAuditLog.where(action: :purge).count }.by(1)
    end

    it "carries kind: attempts in the metadata" do
      post settings_security_attempts_purge_path,
           params: { ip: "9.9.9.9", confirm: "yes" }

      log = AuthAuditLog.where(action: :purge).order(:created_at).last
      expect(log.target_type).to eq("LoginAttempt")
      expect(log.metadata["kind"]).to eq("attempts")
      expect(log.metadata["deleted_count"]).to be >= 1
    end
  end
end
