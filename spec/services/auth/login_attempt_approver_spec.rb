require "rails_helper"

# Phase 25 — 01c. LoginAttemptApprover specs.
RSpec.describe Auth::LoginAttemptApprover do
  include ActiveSupport::Testing::TimeHelpers

  let(:user)         { create(:user) }
  let(:operator)     { create(:user) }
  let(:fp)           { Digest::SHA256.hexdigest("approver-fp-1") }
  let(:ip_prefix)    { "10.50.0.0/24" }
  let(:pending)     { create(:session, :pending, user: user) }
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
    it "promotes the pending session to active" do
      result = described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :web
      )
      expect(result[:session].id).to eq(pending.id)
      expect(pending.reload.state_active?).to be true
    end

    it "writes a fresh attempt row with reason: approved_from_web" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to change(LoginAttempt, :count).by(1)

      success_row = LoginAttempt.where(result: :success).recent.first
      expect(success_row.reason).to eq("approved_from_web")
    end

    it "carries the source-specific reason for tui" do
      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :tui
      )
      success_row = LoginAttempt.where(result: :success).recent.first
      expect(success_row.reason).to eq("approved_from_tui")
    end

    it "carries the source-specific reason for mcp" do
      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :mcp
      )
      success_row = LoginAttempt.where(result: :success).recent.first
      expect(success_row.reason).to eq("approved_from_mcp")
    end

    it "upserts a TrustedLocation row for the (user, fp, prefix) triple" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to change(TrustedLocation, :count).by(1)

      row = TrustedLocation.last
      expect(row.user_id).to eq(user.id)
      expect(row.fingerprint_hash).to eq(fp)
      expect(row.ip_prefix).to eq(ip_prefix)
    end

    it "rotates the session token (digest changes)" do
      original = pending.token_digest
      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :web
      )
      expect(pending.reload.token_digest).not_to eq(original)
    end

    it "writes an audit row with action: approve and source: web" do
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to change(AuthAuditLog, :count).by(1)

      row = AuthAuditLog.last
      expect(row.action).to eq("approve")
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

    it "is a no-op on a notification that is already read" do
      notif = create(:notification, :with_dedup_key,
                     kind: :login_pending_approval,
                     event_type: "login_pending_approval",
                     severity: :urgent,
                     in_app_read_at: 1.hour.ago)
      attempt.update!(notification: notif)
      stamped = notif.in_app_read_at

      described_class.call(
        login_attempt: attempt,
        acting_user: operator,
        source: :web
      )
      expect(notif.reload.in_app_read_at.to_i).to eq(stamped.to_i)
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
      }.to raise_error(Auth::LoginAttemptApprover::PendingExpired)
    end

    it "raises AlreadyResolved when the session is already revoked" do
      pending.revoke!
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptApprover::AlreadyResolved)
    end

    it "raises AlreadyResolved when the session is already :expired" do
      pending.update_columns(state: Session.states[:expired])
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptApprover::AlreadyResolved)
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
      }.to raise_error(Auth::LoginAttemptApprover::AlreadyResolved)
    end

    it "raises AlreadyResolved when the session row no longer exists" do
      attempt.update_columns(session_id: 999_999_999)
      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error(Auth::LoginAttemptApprover::AlreadyResolved)
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
          source: :email
        )
      }.to raise_error(ArgumentError, /invalid source/)
    end
  end

  describe ".call (transactional integrity)" do
    it "rolls back the activation if audit-log write fails" do
      allow(Auth::AuditLogger).to receive(:call).and_raise("audit blew up")
      original_state = pending.state

      expect {
        described_class.call(
          login_attempt: attempt,
          acting_user: operator,
          source: :web
        )
      }.to raise_error("audit blew up")

      expect(pending.reload.state).to eq(original_state)
      expect(LoginAttempt.where(result: :success).count).to eq(0)
    end
  end

  describe ".call (defense-in-depth: contract is strict)" do
    it "never reads request-supplied user id from params" do
      # The service signature ONLY accepts `acting_user:` as a kwarg.
      # Confirm by inspecting method arity / kwargs — there must be no
      # `params:` or implicit user resolution.
      params = described_class.method(:call).parameters
      kwarg_names = params.select { |type, _| %i[key keyreq].include?(type) }.map(&:last)
      expect(kwarg_names).to include(:acting_user, :login_attempt, :source)
      expect(kwarg_names).not_to include(:params)
    end
  end
end
