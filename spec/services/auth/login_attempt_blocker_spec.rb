require "rails_helper"

# Phase 25 — 01c. LoginAttemptBlocker specs.
RSpec.describe Auth::LoginAttemptBlocker do
  let(:user)         { create(:user) }
  let(:operator)     { create(:user) }
  let(:fp)           { Digest::SHA256.hexdigest("blocker-fp-1") }
  let(:ip_prefix)    { "10.60.0.0/24" }
  let(:pending)      { create(:session, :pending, user: user) }
  let!(:attempt) do
    create(:login_attempt, :pending,
           user: user,
           fingerprint_hash: fp,
           ip_prefix: ip_prefix,
           session: pending)
  end

  before do
    Auth::GeoEnricher.reset_deferred!
    allow(Auth::GeoEnricher).to receive(:db_available?).and_return(false)
  end

  describe ".call (happy)" do
    it "revokes the pending session" do
      result = described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :web
      )
      expect(result[:session].id).to eq(pending.id)
      expect(pending.reload.state_revoked?).to be true
      expect(pending.reload.revoked_at).to be_present
    end

    it "creates a BlockedLocation row for the (fp, ip_prefix) pair" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to change(BlockedLocation, :count).by(1)

      row = BlockedLocation.last
      expect(row.fingerprint_hash).to eq(fp)
      expect(row.ip_prefix).to eq(ip_prefix)
      expect(row.blocked_by_user_id).to eq(operator.id)
      expect(row.source_web?).to be true
    end

    it "honors the source surface on the BlockedLocation row" do
      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :mcp
      )
      expect(BlockedLocation.last.source_mcp?).to be true
    end

    it "writes a fresh attempt row with reason: blocked_from_web" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to change(LoginAttempt, :count).by(1)

      row = LoginAttempt.where(result: :blocked).recent.first
      expect(row.reason).to eq("blocked_from_web")
      expect(row.fingerprint_hash).to eq(fp)
      expect(row.session_id).to eq(pending.id)
    end

    it "writes a tui-source attempt row when source: tui" do
      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :tui
      )
      expect(LoginAttempt.where(reason: :blocked_from_tui).count).to eq(1)
    end

    it "writes an mcp-source attempt row when source: mcp" do
      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :mcp
      )
      expect(LoginAttempt.where(reason: :blocked_from_mcp).count).to eq(1)
    end

    it "writes an audit row with action: block and source: web" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.last
      expect(row.action).to eq("block")
      expect(row.source_surface).to eq("web")
      expect(row.acting_user_id).to eq(operator.id)
      expect(row.target_type).to eq("LoginAttempt")
      expect(row.target_id).to eq(attempt.id)
    end

    it "resolves the linked notification (marks read)" do
      notif = create(:notification, :with_dedup_key,
                     kind: :login_pending_approval,
                     event_type: "login_pending_approval",
                     severity: :urgent,
                     in_app_read_at: nil)
      attempt.update!(notification: notif)

      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :web
      )
      expect(notif.reload.read?).to be true
    end

    it "stamps a custom reason text on the BlockedLocation row when supplied" do
      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :web,
        reason: "suspicious — known bad fingerprint"
      )
      expect(BlockedLocation.last.reason).to eq("suspicious — known bad fingerprint")
    end
  end

  describe ".call (idempotency on block list)" do
    it "does NOT duplicate a BlockedLocation row when the pair is already blocked" do
      create(:blocked_location,
             fingerprint_hash: fp, ip_prefix: ip_prefix,
             blocked_by_user: operator)

      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.not_to change(BlockedLocation, :count)
    end

    it "still writes a fresh audit row when the pair is already blocked" do
      create(:blocked_location,
             fingerprint_hash: fp, ip_prefix: ip_prefix,
             blocked_by_user: operator)

      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to change(AuthAuditLog, :count).by(1)
    end
  end

  describe ".call (sad)" do
    it "raises PendingExpired when the pending session window has elapsed" do
      pending.update_columns(approval_required_until: 1.minute.ago)
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptBlocker::PendingExpired)
    end

    it "raises AlreadyResolved when the session is already revoked" do
      pending.revoke!
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptBlocker::AlreadyResolved)
    end

    it "raises AlreadyResolved when the session is already :expired" do
      pending.update_columns(state: Session.states[:expired])
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptBlocker::AlreadyResolved)
    end

    it "raises AlreadyResolved when the attempt has no session_id" do
      orphan = create(:login_attempt, :pending,
                      user: user, session: nil,
                      fingerprint_hash: fp, ip_prefix: ip_prefix)
      expect {
        described_class.call(
          login_attempt: orphan,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptBlocker::AlreadyResolved)
    end

    it "raises AlreadyResolved when the session row no longer exists" do
      attempt.update_columns(session_id: 999_999_999)
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptBlocker::AlreadyResolved)
    end

    it "raises ArgumentError on missing login_attempt" do
      expect {
        described_class.call(
          login_attempt: nil,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(ArgumentError, /login_attempt/)
    end

    it "raises ArgumentError on missing acting_user" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: nil,
          source: :web
        )
      }.to raise_error(ArgumentError, /acting_user/)
    end

    it "raises ArgumentError on invalid source" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :sms
        )
      }.to raise_error(ArgumentError, /invalid source/)
    end
  end

  describe ".call (transactional integrity)" do
    it "rolls back the revoke if audit-log write fails" do
      allow(Auth::AuditLogger).to receive(:call).and_raise("audit blew up")

      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error("audit blew up")

      # The whole block (block-list upsert, revoke, attempt row) is
      # rolled back together with the audit-log failure.
      expect(pending.reload.state_pending_approval?).to be true
      expect(BlockedLocation.count).to eq(0)
      expect(LoginAttempt.where(reason: :blocked_from_web).count).to eq(0)
    end
  end
end
